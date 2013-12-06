# A minimal implementation of STUN.  This has just enough code to discover
# our public IP address and port (which is used for UDP NAT hole punching).

require 'socket'
require 'ipaddr'

module STUN
  DEFAULT_PORT = 3478
  HEADER_FORMAT = 'nnNNNN'

  def self.start

  end

  def self.on_port_discovered &block
    @on_port_discovered = block
  end

  def self.bind addr
    addr, port = addr.split ':'
    port ||= DEFAULT_PORT

    socket = UDPSocket.new
    socket.bind '0.0.0.0', 0

    type = 0x0001 # BIND request
    len = 0
    magic = 0x2112A442
    id1 = rand 2**32
    id2 = rand 2**32
    id3 = rand 2**32

    header = [
      type,
      len,
      magic,
      id1,
      id2,
      id3,
    ]

    packet = header.pack HEADER_FORMAT

    warn "Sending to #{addr}:#{port}"

    socket.send packet, 0, addr, port

    res, src = socket.recvfrom 2048

    warn "Got packet in response, size is #{res.size}"

    res_header = res[0...20].unpack HEADER_FORMAT

    res_type = res_header[0]
    res_len = res_header[1]
    res_magic = res_header[2]
    res_id1 = res_header[3]
    res_id2 = res_header[4]
    res_id3 = res_header[5]

    raise "Unexpected reply type: #{res_type}" unless res_type == 0x0101
    raise "Unexpected magic: #{res_magic}" unless res_magic == magic
    unless id1 == res_id1 && id2 == res_id2 && id3 == res_id3
      raise "Unexpected transaction id: #{id1} #{id2} #{id3} != #{res_id1} #{res_id2} #{res_id3}"
    end

    data = res[20..-1]

    warn "Body is #{hex(data)}"

    # Decode attributes
    while data.size > 0
      type, len = data[0...4].unpack 'nn'
      payload = data[4...(4+len)]

      warn "Type is #{type.to_s(16)}, Len is #{len}, Payload is #{hex(data)}"

      # Pad len to four byte boundary
      len += len % 4
      data = data[(4+len)..-1]

      case type
      when 0x0001
        warn "Got old mapped address"
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
        warn "Got xor"
        # XOR-mapped address
        ignored, family, xor_port = payload[0...4].unpack 'nn'
        port = xor_port ^ (magic & 0xffff)

        case family
        when 0x01 # IPv4
          xor_addr = payload[4...8].unpack('nN').first
          addr = xor_addr ^ magic
          port = xor_port ^ (magic & 0xffff)
          port, addr = Socket.unpack_sockaddr_in([port, addr].pack 'nN')
        when 0x02 # IPv6
          xor_part1, xor_part2, xor_part3, xor_part4 = payload[4...20].unpack 'NNNN'
          part1 = xor_part1 ^ magic
          part2 = xor_part2 ^ id1
          part3 = xor_part3 ^ id2
          part4 = xor_part4 ^ id3
          addr = (part1 << 96) + (part2 << 64) + (part3 << 32) + part4
        else
          raise "Invalid IP family: 0x#{family.to_s(16)}"
        end
      else
        warn "Skipping STUN response attribute of type: 0x#{type.to_s(16)}"
      end

      warn "Server says we're running on #{addr}:#{port}" if addr
    end
  end

  def self.hex str
    str.unpack('H*').first
  end
end
