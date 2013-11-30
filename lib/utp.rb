# Pure ruby implementation of uTP (http://www.bittorrent.org/beps/bep_0029.html)

require_relative 'simple_thread'
require_relative 'simple_condition'
require_relative 'buffered_io'
require_relative 'socket_multiplier'

class UTPSocket
  Packet = Struct.new :type, :ver, :extension, :connection_id,
                      :timestamp_microseconds, :timestamp_difference_microseconds,
                      :wnd_size, :seq_nr, :ack_nr,
                      :src, :data

  include BufferedIO

  class Packet
    def self.parse addr, data

    end

    def to_binary
      String.new
    end

    def to_s
    end
  end

  def self.setup socket
    # All packets are going to come in on a single UDP socket, so a dedicated
    # thread will divvy incoming packets out to the appropriate objects via
    # Queues.
    @@objects ||= {}
    @incoming = Queue.new
    @@socket = socket
    SocketMultiplier.setup socket
    SocketMultiplier.on_recvfrom do |data, addr|
      self.handle_incoming_packet data, addr
    end
  end

  def self.accept
    addr = gunlock { @@incoming.shift }
    self.new addr[3], addr[1]
  end

  def initialize addr, port
    client_id = "#{addr}:#{port}"

    # Queue for incoming data packets.  The thread that reads the data off the
    # socket isn't the thread that will be in the middle of a read() or gets()
    # call.
    @queue = Queue.new

    # Extra incoming data.  We have to simulate a stream, so sometimes a
    # packet will come in with more data than the maximum the user requested
    # with readpartial().  We store it here.
    @extra_data = String.new

    # Buffer of data for BufferedIO
    @buffer = String.new

    # Window of packets that are currently "in flight" to our peer.  Each
    # packet stays in this array until it we receive an ACK for it.
    @window = []

    @window_has_room = SimpleCondition.new

    @socket = @@socket

    @@objects[client_id] = self
  end

  def unbuffered_readpartial maxlen
    # Even though this should be unbuffered, we have to implement our own
    # incoming buffer because we can't limit the size of incoming packets.
    #
    # Luckily we can drain it immediately which keeps things simple.
    if @buffer.size > 0
      amount = [@buffer.size, maxlen].min
      slice = @buffer[0...amount]
      @buffer = @buffer[amount..-1]
      return slice
    end

    packet = gunlock { @queue.shift }

    # Since the packet might be bigger than maxlen, we'll need to split it,
    # which we can let our buffer splitter code above do if add the data to the
    # buffer and recurse.
    @buffer << packet.data
    return unbuffered_readpartial maxlen
  end

  def write data
    while data.size > 0
      # If our window is full then we need to block.
      while window.full?
        @window_has_room.wait
      end
      packet = Packet.new
      packet.timestamp_microseconds = now
      amount = [data.size, max_packet_size].min
      packet.data = data[0...amount]
      data = data[amount..-1]

      window << packet
      send_packet packet
    end
  end

  private
  def self.handle_incoming_packet data, addr
    packet = Packet.parse addr, data
    client_id = "#{addr[3]}:#{addr[1]}"
    if packet.new_session?
      @@incoming.push addr
      return true
    end

    if socket = @@objects[client_id]
      socket.handle_incoming_packet packet
      return true
    end

    Log.warn "Received unexpected #{packet} from #{client_id}"
    false
  end

  def send_packet packet
    @socket.send packet.to_binary
  end

  # Handle all incoming packets
  def handle_incoming_packet packet
    if packet.ack?
      # Move window forward
      while window[0].seq_no <= packet.ack_no
        window.shift
      end
      # Notify senders (if any) that the window is no longer full
      @window_has_room.signal
      return
    end

    # FIXME Sending an ack for every incoming packet is inefficient.  If we
    # delay a small amount of time we can send a single ACK to ack multiple
    # packets.
    #
    # We can have the same thread that does retransmissions handle sending out
    # ACKs, since it will be a similar job.
    ack = Packet.new
    ack.flags = ACK
    ack.timestamp_difference_microseconds = packet.timestamp_microseconds - now
    send_packet ack

    @queue << packet
  end
end
