require 'minitest/autorun'

require 'tempfile'
require 'openssl'

require_relative '../lib/message'

def new_path
  path = Tempfile.new('clearskies').path
  File.unlink path
  path
end

describe Message, "serializing" do
  describe "turns into a byte stream" do
    it "should make json of objects" do
      path = new_path
      file = File.open path, 'wb'
      data = { a: 1, b: 2 }
      message = Message.new :test, data.dup
      message[:c] = 3
      message.write_to_io file
      file.close
      File.size(path).must_be :>, 10

      message = Message.read_from_io File.open( path, 'rb' )
      message.type.must_equal :test
      message[:a].must_equal 1
      message[:b].must_equal 2
      message[:c].must_equal 3
      message.binary_payload?.wont_equal true
      message.signed?.wont_equal true
      File.unlink path
    end

    it "should handle binary streams" do
      path = new_path
      file = File.open path, 'wb'
      message = Message.new :test_bin
      count = 0
      message.binary_payload do
        count += 1
        if count < 1000
          "fake#{count}"
        else
          nil
        end
      end

      message.write_to_io file
      file.close

      File.size(path).must_be :>, 8000

      message = Message.read_from_io File.open( path, 'rb' )
      message.type.must_equal :test_bin
      message.binary_payload?.must_equal true
      count = 0
      while data = message.read_binary_payload
        count += 1
        data.must_equal "fake#{count}"
      end
      count.must_equal 999
      File.unlink path
    end

    it "should be signable" do
      path = new_path
      file = File.open path, 'wb'
      message = Message.new :test_sig, {ha: "ho"}

      private_key = OpenSSL::PKey::RSA.generate(512)
      message.sign private_key
      message.write_to_io file
      file.close

      message = Message.read_from_io File.open( path, 'rb' )
      message.signed?.must_equal true
      message.verify(private_key.public_key).must_equal true

      File.unlink path
    end
  end
end
