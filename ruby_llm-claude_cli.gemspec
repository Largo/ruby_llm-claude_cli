# frozen_string_literal: true

require_relative 'lib/ruby_llm/claude_cli/version'

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-claude_cli'
  spec.version = RubyLLM::ClaudeCLI::VERSION
  spec.authors = ['Andreas Idogawa']
  spec.summary = 'RubyLLM provider that runs chats through the local `claude -p` CLI'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'
  spec.files = Dir['lib/**/*.rb', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '~> 2.0'
  # Optional: rubyzip enables text extraction from docx/xlsx/pptx attachments.
end
