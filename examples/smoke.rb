# frozen_string_literal: true

# Exercises every feature against the real `claude -p`. Usage:
#   ruby examples/smoke.rb [model]      (default: haiku)
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'ruby_llm/claude_cli'
require 'fileutils'
require 'zip'

MODEL = ARGV[0] || 'haiku'
FIX = File.expand_path('../tmp/fixtures', __dir__)
FileUtils.mkdir_p(FIX)

def chat = RubyLLM.chat(model: MODEL, provider: :claude_cli)

def check(name)
  print "#{name.ljust(28)} "
  t = Time.now
  out = yield
  puts "ok (#{(Time.now - t).round(1)}s) #{out.to_s.gsub(/\s+/, ' ')[0, 90]}"
rescue StandardError => e
  puts "FAIL #{e.class}: #{e.message[0, 300]}"
end

# fixtures
File.binwrite("#{FIX}/red.png", ['89504E470D0A1A0A0000000D4948445200000001000000010802000000907753DE0000000C4944415408D763F8CFC000000301010018DD8DB00000000049454E44AE426082'].pack('H*'))
File.binwrite("#{FIX}/code.pdf", "%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj 2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj 3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 100]/Contents 4 0 R/Resources<</Font<</F1 5 0 R>>>>>>endobj 4 0 obj<</Length 44>>stream\nBT /F1 18 Tf 20 40 Td (Codeword ZEBRA) Tj ET\nendstream endobj 5 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF")
File.write("#{FIX}/notes.csv", "fruit,count\napple,3\npear,7\n")
FileUtils.rm_f("#{FIX}/memo.docx")
Zip::File.open("#{FIX}/memo.docx", create: true) do |z|
  z.get_output_stream('[Content_Types].xml') { |f| f.write('<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>') }
  z.get_output_stream('word/document.xml') { |f| f.write('<w:document xmlns:w="w"><w:body><w:p><w:r><w:t>The secret animal is OTTER.</w:t></w:r></w:p></w:body></w:document>') }
end
File.binwrite("#{FIX}/blob.bin", "MAGIC-PELICAN\x00\x01\x02")

class Weather < RubyLLM::Tool
  description 'Current temperature for a city'
  parameter :city, description: 'City name'
  def execute(city:) = "#{city}: 17 degrees C, light rain"
end

check('plain ask') { chat.ask('Reply with exactly: pong').content }
check('system prompt') { chat.with_instructions('Always answer in German.').ask('Say hello.').content }
check('streaming') do
  n = 0
  msg = chat.ask('Count from 1 to 20, comma separated.') { |c| n += 1 if c.content && !c.content.empty? }
  "#{n} chunks, tokens in=#{msg.tokens.input} out=#{msg.tokens.output} | #{msg.content}"
end
check('multi-turn memory') do
  c = chat
  c.ask('My favourite number is 42. Just say ok.')
  c.ask('What is my favourite number?').content
end
check('image') { chat.ask('What colour is this pixel? One word.', with: "#{FIX}/red.png").content }
check('pdf') { chat.ask('What is the codeword?', with: "#{FIX}/code.pdf").content }
check('csv') { chat.ask('How many pears?', with: "#{FIX}/notes.csv").content }
check('docx (extracted)') { chat.ask('What is the secret animal?', with: "#{FIX}/memo.docx").content }
check('binary (staged+Read)') { chat.ask('What ASCII word is at the start of the attached file?', with: "#{FIX}/blob.bin").content }
check('image in history') do
  c = chat
  c.ask('Remember this image. Say ok.', with: "#{FIX}/red.png")
  c.ask('What colour was the image?').content
end
check('tool call') { chat.with_tools(Weather).ask('What is the weather in Zurich?').content }
check('structured output') do
  schema = { type: 'object', properties: { city: { type: 'string' }, country: { type: 'string' } },
             required: %w[city country], additionalProperties: false }
  chat.with_schema(schema).ask('Capital of Switzerland?').content
end
check('tool + streaming') { chat.with_tools(Weather).ask('Weather in Bern?') { |_c| }.content }
