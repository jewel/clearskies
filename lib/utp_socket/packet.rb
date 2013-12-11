# Serializer and deserializer for uTP packets.  See ../utp.rb
#
# http://www.bittorrent.org/beps/bep_0029.html

class UTPSocket
  Packet = Struct.new :type, :connection_id,
                      :timestamp, :timestamp_diff,
                      :wnd_size, :seq_nr, :ack_nr, :extensions,
                      :data, :src
end

class UTPSocket::Packet
  # Header layout (from the spec)
  #
  #   0       4       8               16              24              32
  #   +-------+-------+---------------+---------------+---------------+
  #   | type  | ver   | extension     | connection_id                 |
  #   +-------+-------+---------------+---------------+---------------+
  #   | timestamp_microseconds                                        |
  #   +---------------+---------------+---------------+---------------+
  #   | timestamp_difference_microseconds                             |
  #   +---------------+---------------+---------------+---------------+
  #   | wnd_size                                                      |
  #   +---------------+---------------+---------------+---------------+
  #   | seq_nr                        | ack_nr                        |
  #   +---------------+---------------+---------------+---------------+
  #
  # The above table turns into the following signature for String#unpack and
  # Array.pack:
  HEADER_FORMAT = 'CCnNNNnn'

  TYPE_NUMBERS = {
    0 => :data,
    1 => :fin,
    2 => :state,
    3 => :reset,
    4 => :syn,
  }

  TYPE_SYMBOLS = Hash[TYPE_NUMBERS.to_a.map &:reverse]

  EXTENSIONS = {
    1 => :selective_ack
  }

  # Decode packet into fields
  def self.parse addr, raw_data
    packet = self.new
    header = raw_data[0...20]
    fields = header.unpack HEADER_FORMAT

    type = fields[0] >> 4
    packet.type = TYPE_NUMBERS[type]
    raise "Invalid packet type (or not uTP packet): #{type.inspect}" unless packet.type

    version = fields[0] & 0b1111
    raise "Packet has wrong version (or not uTP packet): #{packet.ver.inspect}" unless version == 1

    packet.connection_id = fields[2]
    packet.timestamp = fields[3]
    packet.timestamp_diff = fields[4]
    packet.wnd_size = fields[5]
    packet.seq_nr = fields[6]
    packet.ack_nr = fields[7]
    packet.src = addr

    raw_data = raw_data[20..-1]

    # Decode extensions
    packet.extensions = {}
    next_extension = fields[1]
    while next_extension != 0
      this_extension = next_extension
      next_extension = raw_data[0].unpack 'C'
      len = raw_data[1].unpack 'C'
      type = EXTENSIONS[this_extension] || this_extension
      packet.extensions[this_extension] = raw_data[2...(len+2)]
      raw_data[(len+2)..-1]
    end

    # All that's left is the packet's data
    packet.data = raw_data

    packet
  end

  def to_binary
    raw_data = String.new

    type = TYPE_SYMBOLS[self.type]
    raise "Invalid type: #{self.type.inspect}" unless type
    first_field = (type << 4) | 1

    # FIXME check all fields for errors, most shouldn't be nil

    header = [
      first_field,
      0,
      connection_id || 0,
      timestamp || 0,
      timestamp_diff || 0,
      wnd_size || 0,
      seq_nr || 0,
      ack_nr || 0,
    ]

    raw_data << header.pack( HEADER_FORMAT )

    # FIXME extensions

    raw_data << data if data
    raw_data
  end

  def to_s
    payload = size > 40 ? (data[0..40] + "...").inspect : data.inspect
    "#{connection_id}-" + case type
    when :syn
      "syn packet"
    when :state
      "ack ##{ack_nr}"
    when :data
      "data ##{seq_nr}: #{payload}"
    when :fin
      "fin packet"
    when :reset
      "reset packet"
    else
      "weird packet"
    end
  end
end
