# frozen_string_literal: true

require_relative 'lib/ruby_llm/claude_cli/version'

Gem::Specification.new do |spec|
  spec.name = 'ruby_llm-claude_cli'
  spec.version = RubyLLM::ClaudeCLI::VERSION
  spec.authors = ['Andreas Idogawa']
  spec.email = ['web@idogawa.com']
  spec.summary = 'RubyLLM provider that runs chats through the local `claude -p` CLI'
  spec.description = 'Use Claude Code (and its subscription login) as a RubyLLM provider: streaming, ' \
                     'images, PDFs, Office files, structured output and emulated tool calls over `claude -p`.'
  spec.homepage = 'https://github.com/Largo/ruby_llm-claude_cli'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2'

  spec.metadata = {
    'source_code_uri' => spec.homepage,
    'changelog_uri' => "#{spec.homepage}/blob/main/CHANGELOG.md",
    'bug_tracker_uri' => "#{spec.homepage}/issues",
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'ruby_llm', '~> 2.0'
  # Optional: rubyzip enables text extraction from docx/xlsx/pptx attachments.
end
