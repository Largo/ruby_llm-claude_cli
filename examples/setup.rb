# frozen_string_literal: true

# Loaded by bin/console and examples/demo.rb. Sets up a chat helper for trying the
# claude -p provider.
require 'bundler/setup'
require 'ruby_llm/claude_cli'

RubyLLM.configure do |c|
  c.claude_cli_timeout = 300
end

# chat            -> new chat on sonnet
# chat('haiku')   -> another model (opus, haiku, claude-opus-5-5, ...)
def chat(model = ENV.fetch('MODEL', 'sonnet')) = RubyLLM.chat(model: model, provider: :claude_cli)

class Weather < RubyLLM::Tool
  description 'Current temperature for a city'
  parameter :city, description: 'City name'
  def execute(city:) = "#{city}: 17 degrees C, light rain"
end
