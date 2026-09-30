# frozen_string_literal: true

# bundle exec ruby examples/demo.rb   (MODEL=haiku for a faster run)
require_relative 'setup'

c = chat
puts c.ask('In one sentence: what is Ruby?').content

print "\nStreaming: "
c.ask('Now count to five, comma separated.') { |chunk| print chunk.content }
puts

puts "\nTool: #{chat.with_tools(Weather).ask('What is the weather in Zurich?').content}"
