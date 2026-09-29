# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'minitest/autorun'
require 'tmpdir'
require 'ruby_llm/claude_cli'

class ContentTest < Minitest::Test
  Config = Struct.new(:claude_cli_attachment_converter)

  def setup
    @dir = Dir.mktmpdir
    @fixtures = File.join(@dir, 'in')
    Dir.mkdir(@fixtures)
  end

  def teardown = FileUtils.rm_rf(@dir)

  def fixture(name, bytes)
    File.join(@fixtures, name).tap { |p| File.binwrite(p, bytes) }
  end

  def user(text, with: nil) = RubyLLM::Message.new(role: :user, content: text, attachments: with)

  def test_single_user_turn_is_passed_through
    blocks = RubyLLM::ClaudeCLI::Content.new(@dir).blocks([user('hi')])
    assert_equal [{ type: 'text', text: 'hi' }], blocks
  end

  def test_history_becomes_transcript_with_tool_calls
    call = RubyLLM::ToolCall.new(id: 't1', name: 'weather', arguments: { 'city' => 'Bern' })
    msgs = [user('weather?'),
            RubyLLM::Message.new(role: :assistant, content: nil, tool_calls: { 't1' => call }),
            RubyLLM::Message.new(role: :tool, content: 'sunny', tool_call_id: 't1')]
    text = RubyLLM::ClaudeCLI::Content.new(@dir).blocks(msgs).map { _1[:text] }.join
    assert_includes text, '<tool_call id="t1" name="weather">{"city":"Bern"}</tool_call>'
    assert_includes text, "<tool_result id=\"t1\">\nsunny"
  end

  def test_binary_is_staged_with_hex_preview
    content = RubyLLM::ClaudeCLI::Content.new(@dir)
    blocks = content.blocks([user('look', with: fixture('x.bin', "HELLO-WORLD\x00\x01"))])
    assert_equal 1, content.staged_files.size
    assert_includes blocks.last[:text], 'strings: HELLO-WORLD'
  end

  def test_converter_hook_wins
    config = Config.new(->(a) { a.filename == 'talk.mp3' ? 'transcript: hello' : nil })
    content = RubyLLM::ClaudeCLI::Content.new(@dir, config)
    blocks = content.blocks([user('sum up', with: fixture('talk.mp3', 'ID3fake'))])
    assert_includes blocks.map { _1[:text] }.join, 'transcript: hello'
    assert_empty content.staged_files
  end

  def test_schema_cleaning_drops_strict
    cleaned = RubyLLM::ClaudeCLI::ToolEmulation.clean({ strict: true, properties: { a: { 'strict' => 1, type: 'x' } } })
    assert_equal({ properties: { a: { type: 'x' } } }, cleaned)
  end
end
