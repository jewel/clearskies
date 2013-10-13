require 'minitest/autorun'
require './lib/base32'

describe Base32, 'binary to text' do
  it 'encodes' do
    Base32.encode('').must_equal ''
    Base32.encode('fooba').must_equal 'MZXW6YTB'
  end

  it 'decodes' do
    Base32.decode('MZXW6YTB').must_equal 'fooba'
    Base32.decode('').must_equal ''
  end
end
