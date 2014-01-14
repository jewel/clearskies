# A clearskies message, as is defined in protocol/core.md
#
# This class serializes and unserializes messages, and can sign and verify
# messages.
#
# Instead of serializing to a string, it serializes to a stream and reads from
# a stream.  This is because a single message can contain the entire contents
# of a single file in the binary payload.  This means that there are methods
# to read the binary payload as a stream so that it can be saved to disk as
# it is received.

require 'json'
require 'openssl'
require 'base64'

class Message
  # Create a message of `type`.
  def initialize type=nil, opts={}
    @signed = false
    @has_binary_payload = false
    @data = opts.clone
    @data[:type] = type
  end

  # Give the type of the message as a symlink
  def type
    self[:type].to_sym
  end

  # Get the JSON data corresponding to `key`
  def [] key
    @data[key]
  end

  # Set data corresponding to `key`
  def []= key, val
    @data[key] = val
  end

  # Is the message signed?
  def signed?
    @signed
  end

  # Does the message have a binary payload?
  def binary_payload?
    @has_binary_payload
  end

  # Set the binary payload.  A block should be given which returns a string
  # every time it is called.  If it returns nil that will be interpreted as the
  # end of the binary data.
  def binary_payload &block
    @has_binary_payload = true
    @binary_payload = block
  end

  # Read the binary payload from the message, in chunks.  Will return nil once
  # no more chunks are available.
  def read_binary_payload
    raise "No binary payload" unless @has_binary_payload
    len = @binary_io.gets
    unless len =~ /\A\d+\n\Z/
      raise "Invalid binary payload chunk boundary: #{len.inspect}"
    end

    len = len.to_i
    return nil if len == 0

    raise "Binary chunk of size #{len} is too large" if len > 16_777_216

    data = @binary_io.read len
    raise "Premature end of stream" if data.nil?
    data
  end

  # Sign the message using the RSA private key given.  This only signs the JSON
  # portion of the message, not the binary payload.
  def sign private_key
    @signed = true
    @private_key = private_key
  end

  # Verify that the message body (JSON portion) was signed by the OpenSSL RSA
  # private key corresponding with the public key given.
  def verify public_key
    raise "Message not signed" unless signed?
    digest = OpenSSL::Digest::SHA256.new
    public_key.verify digest, @signature, @signed_message
  end

  # Class method to read a message from any IO, typically a socket.
  def self.read_from_io io
    m = self.new
    m.read_from_io io
    m
  end

  # Read message from IO, typically a socket.  Note that if the message has
  # binary data it won't be read, that MUST be read using multiple calls to
  # read_binary_data before calling read_from_io again.
  def read_from_io io
    msg = io.gets
    raise "Connection lost" unless msg
    first = msg[0]

    if first == '$'
      @signed = true
      msg = msg[1..-1]
      first = msg[0]
    end

    if first == '!'
      @has_binary_payload = true
      @binary_io = io
      msg = msg[1..-1]
      first = msg[0]
    end

    if first != '{'
      raise "Message not JSON object: #{msg.inspect}"
    end

    @data = JSON.parse msg, symbolize_names: true
    raise "Message has no type: #{@data.inspect}" unless @data[:type]

    if @signed
      @signature = Base64.decode64 io.gets
      @signed_message = msg.chomp
    end
  end

  # Serialize message to IO.
  def write_to_io io
    if @private_key
      digest = OpenSSL::Digest::SHA256.new
      signature = @private_key.sign digest, @data.to_json
      signature = Base64.encode64 signature
      signature.gsub! "\n", ""
    end

    binary_data = nil

    msg = ""
    msg << "$" if @private_key
    msg << "!" if @has_binary_payload
    msg << @data.to_json

    raise "No newlines allowed in JSON" if msg =~ /\n/

    io.write msg + "\n"

    if signature
      io.write signature + "\n"
    end

    if @has_binary_payload
      while data = @binary_payload.call
        io.puts data.size.to_s
        io.write data
      end

      io.puts 0.to_s
    end
  end

  # Serialize message to string for debug messages
  def to_s
    str = "#{@data[:type].upcase} "

    obj = @data.dup
    obj.delete :type

    str << obj_to_str(obj)

    str << " (signed)" if @signed
    str << " (binary)" if @has_binary_payload

    str
  end

  private
  # Part of to_s debug serializer.  This is similar to the format that .inspect
  # gives, but shortens hexidecimal hashes for better legibility.
  def obj_to_str obj
    case obj
    when String
      if obj =~ /\A[0-9a-f]{16,}\Z/
        "\"#{obj[0..8]}...\""
      else
        obj.inspect
      end
    when Hash
      "{ " + (obj.map { |key,val| "#{key}: #{obj_to_str(val)}" }).join( ", " ) + " }"
    when Array
      "[ " + (obj.map { |val| obj_to_str val }).join( ", " ) + " ]"
    else
      obj.inspect
    end
  end
end
