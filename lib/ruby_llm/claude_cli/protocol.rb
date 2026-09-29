# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'

module RubyLLM
  module ClaudeCLI
    # Reuses the Anthropic protocol's response and stream parsing, and swaps
    # the HTTP request for a `claude -p` process. The CLI's stream-json output
    # carries raw Messages API events, so build_chunk reads them as-is.
    class Protocol < Protocols::Anthropic
      EFFORTS = %w[low medium high xhigh max].freeze
      DEFAULT_SYSTEM_PROMPT = 'You are a helpful assistant.'

      # The payload stays a plain description of the request; the CLI
      # arguments are built when it runs, next to its work directory.
      def render_payload(messages, tools:, temperature:, model:, stream: false, max_output_tokens: nil,
                         schema: nil, thinking: nil, citations: false, caching: nil, tool_prefs: nil) # rubocop:disable Lint/UnusedMethodArgument
        if temperature || max_output_tokens
          RubyLLM.logger.debug { 'claude-cli: temperature and max_output_tokens are not supported, ignoring' }
        end
        { model: model.id, messages: messages, tools: tools, tool_prefs: tool_prefs || {},
          schema: schema, thinking: thinking, stream: stream }
      end

      def count_tokens(*, **)
        raise RubyLLM::Error, 'claude_cli does not support token counting'
      end

      def preprocess_message(message)
        message
      end

      private

      def auto_upload_large_files? = false
      def supports_provider_file_references? = false

      def sync_response(payload, _headers = {})
        run_cli(payload)
      end

      def stream_response(payload, _headers = {}, &)
        run_cli(payload, &)
      end

      def run_cli(payload, &block)
        workdir = make_workdir
        request, emulate = build_request(payload, workdir, stream: !block.nil?)
        model_id = nil
        @cli_blocks = {}

        result = Runner.new(@config).run(request) do |event|
          model_id ||= event.dig('message', 'model') if event['type'] == 'assistant'
          forward_stream_event(event, &block) if request.stream
        end

        message = parse_completion_body(response_body(result, payload, emulate, model_id), raw: result)
        block&.call(Chunk.new(role: :assistant, content: message.content, model: message.model)) unless request.stream
        message
      ensure
        FileUtils.rm_rf(workdir) if workdir && !@config.claude_cli_workdir
      end

      def build_request(payload, workdir, stream:)
        content = Content.new(workdir, @config)
        system_messages, chat_messages = payload[:messages].partition { |m| m.role == :system }
        blocks = content.blocks(chat_messages)

        system_prompt = content.system_prompt(system_messages)
        system_prompt = @config.claude_cli_default_system_prompt || DEFAULT_SYSTEM_PROMPT if system_prompt.empty?

        tools = ToolEmulation.active_tools(payload[:tools] || {}, payload[:tool_prefs])
        emulate = tools.any?
        json_schema = if emulate
                        system_prompt = "#{system_prompt}\n\n#{ToolEmulation.instructions(tools, payload[:tool_prefs])}"
                        ToolEmulation.schema(tools, payload[:tool_prefs], payload[:schema])
                      elsif payload[:schema]
                        ToolEmulation.user_schema_body(payload[:schema])
                      end

        native = Array(@config.claude_cli_native_tools).map(&:to_s)
        native |= ['Read'] if content.staged_files.any?

        request = Runner::Request.new(
          model: payload[:model], system_prompt:, content: blocks, json_schema:,
          effort: effort(payload[:thinking]),
          # Structured replies stream as StructuredOutput tool input, not text.
          stream: stream && json_schema.nil?,
          tools: native, add_dirs: [], workdir:
        )
        [request, emulate]
      end

      def effort(thinking)
        value = thinking.respond_to?(:effort) ? thinking.effort.to_s : ''
        EFFORTS.include?(value) ? value : nil
      end

      def make_workdir
        base = @config.claude_cli_workdir
        return Dir.mktmpdir('ruby_llm_claude_cli') unless base

        FileUtils.mkdir_p(base)
        base
      end

      # Only text from the top-level agent reaches the caller: tool_use
      # blocks of native CLI tools would otherwise look like ruby_llm tool
      # calls.
      def forward_stream_event(event)
        return unless event['type'] == 'stream_event' && event['parent_tool_use_id'].nil?

        data = event['event']
        case data['type']
        when 'message_start'
          @cli_blocks = {}
        when 'content_block_start'
          @cli_blocks[data['index']] = data.dig('content_block', 'type')
          return unless @cli_blocks[data['index']] == 'text'
        when 'content_block_delta', 'content_block_stop'
          return unless @cli_blocks[data['index']] == 'text'
        when 'message_delta', 'message_stop'
          nil
        else
          return
        end
        yield build_chunk(data)
      end

      def response_body(result, payload, emulate, model_id)
        blocks = if emulate
                   ToolEmulation.blocks(result['structured_output'], payload[:schema])
                 elsif payload[:schema]
                   [{ 'type' => 'text', 'text' => JSON.generate(result['structured_output']) }]
                 else
                   [{ 'type' => 'text', 'text' => result['result'].to_s }]
                 end
        stop = if blocks.any? { |b| b['type'] == 'tool_use' } then 'tool_use'
               elsif result['stop_reason'] == 'tool_use' then 'end_turn'
               else result['stop_reason']
               end
        { 'content' => blocks, 'usage' => result['usage'] || {}, 'stop_reason' => stop,
          'model' => model_id || payload[:model] }
      end
    end
  end
end
