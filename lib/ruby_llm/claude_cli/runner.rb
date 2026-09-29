# frozen_string_literal: true

require 'json'
require 'open3'
require 'timeout'

module RubyLLM
  module ClaudeCLI
    # Starts one `claude -p` process, feeds it a stream-json user message and
    # yields every JSON event it prints. Returns the final "result" event.
    class Runner
      Request = Struct.new(:model, :system_prompt, :content, :json_schema, :effort,
                           :stream, :tools, :add_dirs, :workdir, keyword_init: true)

      def initialize(config)
        @config = config
      end

      def run(request)
        args = build_args(request)
        RubyLLM.logger.debug { "claude-cli: #{args.reject { |a| a.length > 200 }.join(' ')}" }
        input = JSON.generate({ type: 'user', message: { role: 'user', content: request.content } })

        Open3.popen3(*args, chdir: request.workdir) do |stdin, stdout, stderr, wait|
          err_reader = Thread.new { stderr.read }
          stdin.binmode.write(input, "\n")
          stdin.close

          result = with_timeout(wait) { read_events(stdout) { |event| yield event if block_given? } }
          status = wait.value
          check!(result, status, err_reader.value)
        end
      end

      def build_args(request)
        args = [command, '-p',
                '--input-format', 'stream-json',
                '--output-format', 'stream-json', '--verbose',
                '--model', request.model,
                '--system-prompt', request.system_prompt,
                '--tools', request.tools.join(','),
                '--no-session-persistence',
                '--setting-sources', '',
                '--strict-mcp-config',
                '--disable-slash-commands']
        args << '--include-partial-messages' if request.stream
        args.push('--allowedTools', request.tools.join(',')) if request.tools.any?
        request.add_dirs.each { |dir| args.push('--add-dir', dir) }
        args.push('--json-schema', JSON.generate(request.json_schema)) if request.json_schema
        args.push('--effort', request.effort) if request.effort
        args.concat(Array(@config.claude_cli_extra_args))
      end

      private

      def command
        @config.claude_cli_command || 'claude'
      end

      def read_events(stdout)
        result = nil
        stdout.each_line do |line|
          next if line.strip.empty?

          event = begin
            JSON.parse(line)
          rescue JSON::ParserError
            RubyLLM.logger.debug { "claude-cli: non-JSON output #{line.inspect}" }
            next
          end
          result = event if event['type'] == 'result'
          yield event
        end
        result
      end

      def with_timeout(wait, &)
        seconds = @config.claude_cli_timeout
        return yield unless seconds

        Timeout.timeout(seconds, &)
      rescue Timeout::Error
        Process.kill('KILL', wait.pid) rescue nil # rubocop:disable Style/RescueModifier
        raise RubyLLM::Error, "claude -p did not finish within #{seconds}s"
      end

      def check!(result, status, stderr)
        if result.nil?
          raise RubyLLM::Error, "claude -p exited (#{status.exitstatus}) without a result: #{stderr.strip}"
        end
        if result['is_error']
          detail = result['result'] || result['errors']&.join('; ') || result['subtype']
          raise RubyLLM::Error, "claude -p failed: #{detail}"
        end

        result
      end
    end
  end
end
