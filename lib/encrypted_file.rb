# Work with encrypted files.  See the core protocol documentation for
# an explanation of the encrypted file format.

require 'openssl'

# This class mostly acts like the "File" class, although it doesn't implement
# methods intended for text data, such as puts and gets.
#
class EncryptedFile
  HEADER_SIZE = 16
  FOOTER_SIZE = 8

  # FIXME this also needs to be able to operate on strings, without
  # a physical file involved
  def initialize path, mode, key
    @path = path
    @mode = mode + 'b'
    @key = key

    @file = File.open @path, @mode
  end

  def self.open path, mode, key
    obj = self.new path, mode, key

    if block_given?
      yield obj
      obj.close
    end
  end

  def self.size path
    File.size( path ) - HEADER_SIZE - FOOTER_SIZE
  end

  def size
    @file.size - HEADER_SIZE - FOOTER_SIZE
  end

  def read size=nil
  end
  alias readpartial :read

  def write data
  end

  def pos
    @file.pos - HEADER_SIZE
  end

  def pos=
  end

  def seek
  end

  # Verify that the SHA256 at the end of the file is correct
  def verify
  end

  def self.binread path, key
    String.new
  end

  def self.binwrite path, key, data
  end
end
