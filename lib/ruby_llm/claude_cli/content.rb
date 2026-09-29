# frozen_string_literal: true

require 'json'
require 'fileutils'

module RubyLLM
  module ClaudeCLI
    # Turns a ruby_llm conversation into the content blocks of the single user
    # message `claude -p` receives.
    #
    # Attachment handling:
    # * png/jpeg/gif/webp up to 5 MB  -> inline image block (URLs are fetched)
    # * PDF up to 20 MB               -> inline document block
    # * text, code, csv, json         -> inline text
    # * docx/xlsx/pptx                -> text extracted from the Office XML
    #                                    (needs the rubyzip gem), else staged
    # * anything, via hook            -> config.claude_cli_attachment_converter
    # * everything else, oversized    -> copied into the work dir and the model
    #   images and PDFs                  is told the path; the Read tool is
    #                                    enabled so it can open it (Read also
    #                                    downsizes big images and pages PDFs);
    #                                    binaries also get a hex preview
    class Content
      INLINE_IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
      MAX_INLINE_IMAGE = 5 * 1024 * 1024
      MAX_INLINE_PDF = 20 * 1024 * 1024
      OFFICE_TEXT_PARTS = {
        'docx' => %r{\Aword/(document|header\d*|footer\d*|footnotes)\.xml\z},
        'pptx' => %r{\Appt/slides/slide\d+\.xml\z},
        'xlsx' => %r{\Axl/(sharedStrings|worksheets/sheet\d+)\.xml\z}
      }.freeze

      attr_reader :staged_files

      def initialize(workdir, config = nil)
        @workdir = workdir
        @config = config
        @staged_files = []
      end

      def system_prompt(system_messages)
        system_messages.map { |msg| text_of(msg) }.reject(&:empty?).join("\n\n")
      end

      # One user turn goes in as-is; longer histories become a tagged
      # transcript, because stream-json input only takes user messages.
      def blocks(messages)
        if messages.one? && messages.first.role == :user
          return message_blocks(messages.first).then { |b| b.empty? ? [text('(empty message)')] : b }
        end

        out = [text("The conversation so far follows. Continue it by writing the assistant's next reply " \
                    "to the last turn. Do not repeat the tags.\n")]
        messages.each { |msg| out.concat(transcript_turn(msg)) }
        merge_texts(out)
      end

      private

      def transcript_turn(msg)
        case msg.role
        when :tool
          [text("<tool_result id=\"#{msg.tool_call_id}\">\n"), *message_blocks(msg), text("\n</tool_result>\n")]
        when :assistant
          calls = (msg.tool_calls || {}).values.map do |call|
            text(%(\n<tool_call id="#{call.id}" name="#{call.name}">#{JSON.generate(call.arguments)}</tool_call>))
          end
          [text("<assistant>\n"), *message_blocks(msg), *calls, text("\n</assistant>\n")]
        else
          [text("<user>\n"), *message_blocks(msg), text("\n</user>\n")]
        end
      end

      def message_blocks(msg)
        parts = []
        body = content_string(msg.content)
        parts << text(body) unless body.empty?
        msg.attachments.each { |attachment| parts.concat(attachment_blocks(attachment)) }
        parts
      end

      def text_of(msg)
        [content_string(msg.content), *msg.attachments.map { |a| a.text? ? a.for_llm : '' }].join("\n").strip
      end

      def content_string(content) = content.to_s

      def attachment_blocks(attachment)
        if (converted = convert(attachment))
          [text("<file name='#{attachment.filename}' mime_type='#{attachment.mime_type}' " \
                "note='converted to text'>#{converted}</file>")]
        elsif attachment.image? && INLINE_IMAGE_TYPES.include?(attachment.mime_type) &&
           attachment.content.bytesize <= MAX_INLINE_IMAGE
          [{ type: 'image', source: { type: 'base64', media_type: attachment.mime_type, data: attachment.encoded } }]
        elsif attachment.pdf? && attachment.content.bytesize <= MAX_INLINE_PDF
          [{ type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: attachment.encoded },
             title: attachment.filename }.compact]
        elsif attachment.text?
          [text(attachment.for_llm)]
        elsif (office = office_text(attachment))
          [text("<file name='#{attachment.filename}' mime_type='#{attachment.mime_type}' " \
                "note='text extracted from the Office file'>#{office}</file>")]
        else
          [text(stage(attachment))]
        end
      end

      # config.claude_cli_attachment_converter = ->(attachment) { ... }
      # returns text for an attachment (e.g. a transcript of audio made with
      # RubyLLM.transcribe on another provider), or nil to fall through.
      def convert(attachment)
        converter = @config&.claude_cli_attachment_converter
        result = converter&.call(attachment)
        result.nil? || result.to_s.empty? ? nil : result.to_s
      end

      def office_text(attachment)
        pattern = OFFICE_TEXT_PARTS[attachment.extension]
        return unless pattern && zip_available?

        require 'stringio'
        texts = []
        Zip::File.open_buffer(StringIO.new(attachment.content)) do |zip|
          zip.entries.select { |e| e.name.match?(pattern) }.sort_by { |e| e.name.scan(/\d+/).map(&:to_i) }.each do |e|
            texts << xml_to_text(e.get_input_stream.read)
          end
        end
        joined = texts.join("\n\n").strip
        joined.empty? ? nil : joined
      rescue StandardError => e
        RubyLLM.logger.debug { "claude-cli: office text extraction failed: #{e.message}" }
        nil
      end

      def xml_to_text(xml)
        xml.force_encoding('UTF-8')
           .gsub(%r{</w:p>|</a:p>|</row>|<w:br/>}, "\n").gsub(%r{</c>|<w:tab/>}, "\t")
           .gsub(/<[^>]+>/, '')
           .gsub('&lt;', '<').gsub('&gt;', '>').gsub('&quot;', '"').gsub('&apos;', "'").gsub('&amp;', '&')
           .gsub(/\n{3,}/, "\n\n")
      end

      def zip_available?
        return @zip_available unless @zip_available.nil?

        @zip_available = begin
          require 'zip'
          true
        rescue LoadError
          false
        end
      end

      def stage(attachment)
        dir = File.join(@workdir, 'attachments')
        FileUtils.mkdir_p(dir)
        name = File.basename(attachment.filename || "file#{@staged_files.size + 1}")
        name = "#{@staged_files.size + 1}-#{name}" if File.exist?(File.join(dir, name))
        path = File.join(dir, name)
        File.binwrite(path, attachment.content)
        @staged_files << path
        size = File.size(path)
        note = "[Attached file '#{name}' (#{attachment.mime_type}, #{size} bytes) is saved at #{path}. "
        note += if attachment.image? || attachment.pdf?
                  'It is too large to inline; open it with the Read tool.]'
                else
                  'The Read tool can open it if it is text. Its first bytes as hex, with printable ' \
                    "strings, are:\n#{hex_preview(attachment.content)}\n" \
                    'If the format cannot be understood from this, say so.]'
                end
        note
      end

      def hex_preview(bytes, limit = 512)
        head = bytes.byteslice(0, limit).b
        lines = head.bytes.each_slice(16).map do |row|
          hex = row.map { |b| format('%02x', b) }.join(' ')
          "#{hex.ljust(47)}  #{row.map { |b| b.between?(32, 126) ? b.chr : '.' }.join}"
        end
        strings = bytes.b.scan(/[\x20-\x7e]{6,}/n).first(40).join(' | ')
        "#{lines.join("\n")}\nstrings: #{strings}"
      end

      def text(value) = { type: 'text', text: value }

      def merge_texts(blocks)
        blocks.each_with_object([]) do |block, out|
          if block[:type] == 'text' && out.last && out.last[:type] == 'text'
            out[-1] = text(out.last[:text] + block[:text])
          else
            out << block
          end
        end
      end
    end
  end
end
