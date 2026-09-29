# frozen_string_literal: true

require 'json'
require 'securerandom'

module RubyLLM
  module ClaudeCLI
    # `claude -p` cannot call back into Ruby, so ruby_llm tools are emulated:
    # the tools are described in the system prompt and the reply is forced
    # through --json-schema into {text, tool_calls}. Tool calls come back to
    # ruby_llm as ordinary ToolCalls, ruby_llm runs them, and the results go
    # into the next request's transcript.
    module ToolEmulation
      module_function

      def active_tools(tools, tool_prefs)
        return [] if tool_prefs[:choice] == :none

        list = tools.values
        choice = tool_prefs[:choice]
        list = list.select { |t| t.name.to_s == choice.to_s } unless choice.nil? || %i[auto required].include?(choice)
        list
      end

      def instructions(tools, tool_prefs)
        specs = tools.map do |tool|
          fn = Protocols::Anthropic::Tools.function_for(tool)
          "- #{fn[:name]}: #{fn[:description]}\n  input schema: #{JSON.generate(fn[:input_schema])}"
        end
        rule = if tool_prefs[:choice] && tool_prefs[:choice] != :auto
                 'You must call at least one tool in this reply.'
               else
                 'Call tools only when they help; otherwise leave tool_calls empty.'
               end
        rule += ' Call at most one tool per reply.' if tool_prefs[:calls] == :one

        <<~TEXT
          # Tools
          You can use these tools, which run on the caller's side:
          #{specs.join("\n")}

          To call tools, put them in "tool_calls" of your structured reply (name + arguments). You will
          see their output in a later turn as <tool_result> blocks; never invent results yourself.
          Put any text for the user in "text". #{rule}
        TEXT
      end

      def schema(tools, tool_prefs, user_schema)
        variants = tools.map do |tool|
          fn = Protocols::Anthropic::Tools.function_for(tool)
          { type: 'object',
            properties: { name: { type: 'string', enum: [fn[:name]] }, arguments: clean(fn[:input_schema]) },
            required: %w[name arguments] }
        end
        calls = { type: 'array', items: variants.one? ? variants.first : { anyOf: variants } }
        calls[:minItems] = 1 if tool_prefs[:choice] && tool_prefs[:choice] != :auto
        calls[:maxItems] = 1 if tool_prefs[:calls] == :one

        properties = { text: { type: 'string' }, tool_calls: calls }
        properties[:final] = user_schema_body(user_schema) if user_schema
        { type: 'object', properties: properties, required: %w[text tool_calls] }
      end

      def user_schema_body(user_schema)
        clean(user_schema[:schema])
      end

      # The CLI validates --json-schema strictly and rejects OpenAI's "strict".
      def clean(schema)
        case schema
        when Hash then schema.reject { |k, _| k.to_s == 'strict' }.transform_values { |v| clean(v) }
        when Array then schema.map { |v| clean(v) }
        else schema
        end
      end

      # Returns Anthropic-style content blocks for the structured reply.
      def blocks(structured, user_schema)
        structured ||= {}
        blocks = []
        text = if user_schema && structured['final'] && Array(structured['tool_calls']).empty?
                 JSON.generate(structured['final'])
               else
                 structured['text'].to_s
               end
        blocks << { 'type' => 'text', 'text' => text } unless text.empty?
        Array(structured['tool_calls']).each do |call|
          blocks << { 'type' => 'tool_use', 'id' => "toolu_cli_#{SecureRandom.hex(10)}",
                      'name' => call['name'], 'input' => call['arguments'] || {} }
        end
        blocks
      end
    end
  end
end
