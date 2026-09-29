# ruby_llm-claude_cli

A [RubyLLM](https://rubyllm.com) 2.x provider that runs chats through the local
`claude -p` (Claude Code) instead of the HTTP API. Requests use whatever login
Claude Code has, including a Pro/Max subscription. No API key is needed.

```ruby
require 'ruby_llm/claude_cli'

chat = RubyLLM.chat(model: 'sonnet', provider: :claude_cli)   # or opus, haiku, claude-opus-5-5
chat.ask('Summarise this', with: 'report.pdf')
chat.ask('Stream please') { |chunk| print chunk.content }
```

## How it works

It subclasses ruby_llm's Anthropic protocol and swaps the HTTP call for a
`claude -p --input-format stream-json --output-format stream-json` process.
The CLI streams raw Messages API events, so ruby_llm's own Anthropic parser
reads the stream. Each call starts a fresh, isolated CLI session with a
throwaway working directory, no settings files, MCP servers, skills or saved
session, and your system prompt in place of Claude Code's.

## What is supported, and the workarounds

| Feature | How |
|---|---|
| Text, system prompts, multi-turn | History is sent as one tagged transcript (stream-json input only accepts user turns) |
| Streaming | Native, from the CLI's partial-message events |
| Images (png/jpeg/gif/webp ≤ 5 MB) | Inline base64 image blocks. URLs are downloaded first. Images in earlier turns are kept. |
| PDFs (≤ 20 MB) | Inline document blocks |
| Text, code, CSV, JSON | Inline text |
| docx / xlsx / pptx | Text is extracted from the Office XML (needs `rubyzip`) |
| Larger images and PDFs | Saved to the working directory. The model opens them with the Read tool, which downsizes images and pages through PDFs. |
| Other binaries | Saved to the working directory, plus a hex and strings preview |
| Audio, video, anything else | `config.claude_cli_attachment_converter` hook, see below |
| Tools (`with_tools`) | Emulated: tools are described in the system prompt and the reply is forced through `--json-schema` into `{text, tool_calls}`. ruby_llm runs the tools as usual. Honours `choice:` and `calls: :one`. |
| Structured output (`with_schema`) | `--json-schema` |
| `with_thinking(effort:)` | `--effort` (low/medium/high/xhigh/max) |
| temperature, max_output_tokens, token counting, citations, caching controls | Not available through the CLI. Ignored, or an error is raised. |

Transcribe audio with another provider before it reaches Claude:

```ruby
RubyLLM.configure do |c|
  c.claude_cli_attachment_converter = lambda do |attachment|
    RubyLLM.transcribe(attachment.source.to_s, model: 'gpt-4o-transcribe').text if attachment.audio?
  end
end
```

## Configuration

```ruby
RubyLLM.configure do |c|
  c.claude_cli_command = 'claude'             # path to the CLI
  c.claude_cli_timeout = 300                  # seconds; kills the process after that
  c.claude_cli_native_tools = %w[WebSearch]   # let Claude Code's own tools run (default: none)
  c.claude_cli_extra_args = ['--max-budget-usd', '1']
  c.claude_cli_workdir = nil                  # fixed dir instead of a fresh temp dir per call
  c.claude_cli_default_system_prompt = 'You are a helpful assistant.'
end
```

## Trade-offs

- Each call starts a process, so there is about 2–4 s of extra latency per turn.
  A tool round trip is two calls.
- The full history is re-sent every turn. There is no `--resume`, so ruby_llm
  stays the source of truth for the conversation.
- Token counts come from the CLI's result. Costs follow your Claude Code plan.

## Tests

```bash
ruby test/content_test.rb        # offline
ruby examples/smoke.rb haiku     # real claude -p calls, ~2 min
```
