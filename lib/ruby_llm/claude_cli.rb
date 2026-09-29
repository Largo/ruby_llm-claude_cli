# frozen_string_literal: true

require 'ruby_llm'
require_relative 'claude_cli/version'
require_relative 'claude_cli/runner'
require_relative 'claude_cli/content'
require_relative 'claude_cli/tool_emulation'
require_relative 'claude_cli/protocol'
require_relative 'claude_cli/provider'

RubyLLM::Provider.register :claude_cli, RubyLLM::ClaudeCLI::Provider
