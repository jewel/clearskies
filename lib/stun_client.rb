# A minimal implementation of STUN.  This has just enough code to discover
# our public IP address and port (which is used for UDP NAT hole punching).

require 'socket'
require 'ipaddr'
require_relative 'simple_thread'
require_relative 'log'

class STUNClient
  DEFAULT_PORT = 3478
  HEADER_FORMAT = 'nnNNNN'
  MAGIC = 0x2112A442

  # FIXME We should run our own STUN server
  # FIXME Let user override STUN server
  SERVER = "stun.l.google.com:19302"

  def initialize socket
    @socket = socket

    @valid_ids = []

    socket.create_channel :stun

    SimpleThread.new 'stun_recv' do
      loop do
        receive_response
      end
    end
  end

  def on_bind &block
    @on_bind = block
  end

  def start
    SimpleThread.new 'stun_send' do
      loop do
        send_bind_request SERVER
        gsleep 60
      end
    end
  end

  def send_bind_request addr
    addr, port = addr.split ':'
    port ||= DEFAULT_PORT

    type = 0x0001 # BIND request
    len = 0

    id1 = MAGIC
    id2 = rand 2**32
    id3 = rand 2**32
    id4 = rand 2**32

    expire_old_ids

    @valid_ids << [Time.new + 60, id1, id2, id3, id4, addr]

    header = [
      type,
      len,
      id1,
      id2,
      id3,
      id4,
    ]

    packet = header.pack HEADER_FORMAT

    @socket.send packet, 0, addr, port

    Log.debug "Sent STUN request to #{addr}:#{port}"
  end

  private
  def receive_response
    res, src = @socket.recv_from_channel :stun

    Log.debug "Received STUN response from #{src.inspect}"

    res_header = res[0...20].unpack HEADER_FORMAT

    res_type = res_header[0]
    res_len = res_header[1]
    res_id1 = res_header[2]
    res_id2 = res_header[3]
    res_id3 = res_header[4]
    res_id4 = res_header[5]

    # Skip non-STUN packets, which come on the same socket
    return unless res_id1 == MAGIC

    orig_id = nil

    @valid_ids.each do |id|
      next unless id[1] == res_id1
      next unless id[2] == res_id2
      next unless id[3] == res_id3
      next unless id[4] == res_id4
      orig_id = id
      break
    end

    unless orig_id
      Log.warn "Got stale or invalid STUN packet from #{src}"
    end

    id1 = orig_id[1]
    id2 = orig_id[2]
    id3 = orig_id[3]
    id4 = orig_id[4]

    raise "Unexpected reply type: #{res_type}" unless res_type == 0x0101
    unless id2 == res_id2 && id3 == res_id3 && id4 == res_id4
      raise "Unexpected transaction id: #{id2} #{id3} #{id4} != #{res_id2} #{res_id3} #{res_id4}"
    end

    data = res[20..-1]

    # Decode attributes
    while data.size > 0
      type, len = data[0...4].unpack 'nn'
      payload = data[4...(4+len)]

      decode_attribute type, payload, orig_id

      # Pad len to four byte boundary
      len += len % 4
      data = data[(4+len)..-1]
    end
  end

  def decode_attribute type, payload, id
    case type
    when 0x0001
      # Mapped Address
      ignored, family, port = payload[0...4].unpack 'CCn'
      case family
      when 0x01 # IPv4
        addr = payload[4...8].unpack('N').first
        addr = IPAddr.new( addr, Socket::AF_INET).to_s
      when 0x02 # IPv6
        part1, part2, part3, part4 = payload[4...20].unpack 'NNNN'
        addr = (part1 << 96) + (part2 << 64) + (part3 << 32) + part4
        addr = IPAddr.new( addr, Socket::AF_INET6 ).to_s
      else
        raise "Invalid IP family: 0x#{family.to_s(16)}"
      end

    when 0x0020
      # XOR-mapped address
      ignored, family, xor_port = payload[0...4].unpack 'nn'
      port = xor_port ^ (MAGIC & 0xffff)

      case family
      when 0x01 # IPv4
        xor_addr = payload[4...8].unpack('nN').first
        addr = xor_addr ^ MAGIC
        port = xor_port ^ (MAGIC & 0xffff)
        port, addr = Socket.unpack_sockaddr_in([port, addr].pack 'nN')
      when 0x02 # IPv6
        xor_part1, xor_part2, xor_part3, xor_part4 = payload[4...20].unpack 'NNNN'
        part1 = xor_part1 ^ id[1]
        part2 = xor_part2 ^ id[2]
        part3 = xor_part3 ^ id[3]
        part4 = xor_part4 ^ id[4]
        addr = (part1 << 96) + (part2 << 64) + (part3 << 32) + part4
      else
        raise "Invalid IP family: 0x#{family.to_s(16)}"
      end
    else
      # Log.debug "Skipping STUN response attribute of type: 0x#{type.to_s(16)}"
    end

    if addr
      Log.info "STUN server #{id[5]} says our UDP port is mapped to #{addr}:#{port}"
      @on_bind.call addr, port if @on_bind
    end
  end

  def hex str
    str.unpack('H*').first
  end

  def expire_old_ids
    now = Time.new
    @valid_ids.delete_if do |id|
      id[0] < now
    end
  end
end
