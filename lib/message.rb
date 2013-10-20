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
require 'base64'

class Message
  def initialize type=nil, opts={}
    @signed = false
    @has_binary_payload = false
    @data = opts.clone
    @data[:type] = type
  end

  def type
    self[:type].to_sym
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

  def binary_payload &block
    @has_binary_payload = true
    @binary_payload = block
  end

  def read_binary_payload
    raise "No binary payload" unless @has_binary_payload
    len = @binary_io.gets
    unless len =~ /\A\d+\n\Z/
      raise "Invalid binary payload chunk boundary: #{len.inspect}"
    end

    len = len.to_i
    return nil if len == 0

    data = @binary_io.read len
    raise "Premature end of stream" if data.nil?
    data
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

  def to_s
    msg = ""
    msg << "$" if @private_key
    msg << "!" if @has_binary_payload
    msg << @data.to_json
  end

  def write_to_io io
    if @private_key
      digest = OpenSSL::Digest::SHA256.new
      signature = @private_key.sign digest, @data.to_json
      signature = Base64.encode64 signature
      signature.gsub! "\n", ""
    end

    binary_data = nil

    msg = self.to_s

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
end
