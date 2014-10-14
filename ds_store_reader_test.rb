gem 'minitest'
require 'minitest/autorun'

require_relative './ds_store_reader'

describe DsStoreReader do
  it 'should see start_of_string in peek_header' do
    reader = DsStoreReader.new("\x00\x00\x00\x10")
    reader.peek_header.must_equal get_header(reader, '@file_id_header')
  end

  it 'should read_string' do
    data   = "\x00\x00\x00\x05\x00h\x00e\x00l\x00l\x00o"
    reader = DsStoreReader.new(data)
    reader.read_string.must_equal 'hello'
  end

  it 'should read_header to ustr' do
    data   = '    ustr'
    reader = DsStoreReader.new(data)
    reader.read_header([get_header(reader, '@ustr_header')])
  end

  def get_header(reader, value)
    reader.instance_variable_get(value)
  end
end

