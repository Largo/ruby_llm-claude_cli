# frozen_string_literal: true

module RubyLLM
  module ClaudeCLI
    # Runs chats through the local `claude -p` command instead of the HTTP API,
    # so requests use whatever login Claude Code has (subscription or key).
    #
    #   require 'ruby_llm/claude_cli'
    #   RubyLLM.chat(model: 'sonnet', provider: :claude_cli).ask('Hi')
    class Provider < RubyLLM::Provider
      protocol :claude_cli, ClaudeCLI::Protocol

      # Never contacted; the transport layer just needs a base URL.
      def api_base
        'http://claude-cli.invalid'
      end

      def self.display_name = 'ClaudeCLI'

      # Model ids are passed straight to --model: aliases (sonnet, opus,
      # haiku) or full ids such as claude-opus-5-5.
      def self.assume_models_exist? = true

      def self.local? = true

      def self.configuration_options
        %i[
          claude_cli_command
          claude_cli_workdir
          claude_cli_native_tools
          claude_cli_extra_args
          claude_cli_timeout
          claude_cli_default_system_prompt
          claude_cli_attachment_converter
        ]
      end
    end
  end
end
