# A clearskies message, as is defined in the core protocol
#
# This class serializes and unserializes messages, and can sign and verify
# signatures.
#
# Instead of serializing to a string, it serializes to a stream and reads from
# a stream.  This is because a single message can contain the entire contents
# of a single file in the binary payload.  This means that there are methods
# to read the binary payload as a stream so that it can be saved to disk as
# it is received.

require 'json'
require 'openssl'

class Message
  def initialize
    @signed = false
    @has_binary_payload = false
    @data = {}
  end

  def [] key
    @data[key]
  end

  def []= key, val
    @data[key] = val
  end

  def signed?
    @signed
  end

  def binary_payload?
    @has_binary_payload
  end

  def binary_payload size, &block
    @binary_payload_length = size
    @binary_payload = block
  end

  def verify public_key
    raise "Message not signed" unless signed?
    digest = OpenSSL::Digest::SHA256.new
    public_key.verify digest, @signature, @signed_message
  end

  def sign private_key
    @signed = true
    @private_key = private_key
  end

  def self.read_from_io io
    m = self.new
    m.read_from_io io
    m
  end

  def read_from_io io
    msg = io.gets
    first = msg[0]

    if first == '$'
      @signed = true
      first = msg[1]
      msg = msg[1..-1]
    end

    if first == '!'
      @has_binary_payload = true
      msg =~ /\A!(\d+)!/ or raise "Invalid message: #{msg.inspect}"
      @binary_payload_length = $1.to_i
      msg = $'
      first = msg[0]
    end

    if first != '{'
      raise "Message not JSON object: #{msg.inspect}"
    end

    @data = JSON.parse msg, symbolize_names: true
    raise "Message has no type: #{@message.inspect}" unless @message[:type]

    if @signed
      @signature = io.gets
      @signed_message = msg.chomp
    end
  end

  def write_to_io io
    json = JSON.stringify( @data )
    msg = ""
    if @private_key
      digest = OpenSSL::Digest::SHA256.new
      signature = @private_key.sign digest, json
      msg << "$"
    end

    binary_data = nil
    if @has_binary_payload
      msg << "!#@binary_payload_length!"
    end

    msg << json

    raise "No newlines allowed in JSON" if msg =~ /\n/

    io.write msg + "\n"

    raise "No newlines allowed in RSA signature" if msg =~ /\n/

    io.write signature + "\n" if signature

    if @has_binary_payload
      len = 0

      while data = @binary_payload.call
        len += data.size
        if len > @binary_payload_length
          raise "More data than promised for binary payload"
        end
        io.write data
      end

      if len < @binary_payload_length
        raise "Less data than promised for binary payload"
      end
    end

    io.write "\n"
  end
end
