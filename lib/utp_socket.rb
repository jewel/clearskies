# Pure ruby implementation of the "Micro Transport Protocol", or uTP
# (http://www.bittorrent.org/beps/bep_0029.html)
#
# uTP is used to give TCP-like semantics over UDP sockets.  UDP is desireable
# because of UDP hole punching for NAT firewalls.
#
# This class mimics the behavior of the regular TCP classes in ruby, where
# possible.  Note that both peers have to connect to each other at the same
# time, so this does not have the concept of "server" and "client" in the
# traditional sense.

require_relative 'simple_thread'
require_relative 'simple_condition'
require_relative 'buffered_io'
require_relative 'utp_socket/packet'

class UTPSocket
  include BufferedIO

  CONNECT_TIMEOUT = 10

  def self.setup socket
    # All packets are going to come in on a single UDP socket, so a dedicated
    # thread will divvy incoming packets out to the appropriate objects via
    # Queues.
    @@objects ||= {}
    @@incoming = Queue.new
    @@socket = socket

    SimpleThread.new 'utp_resend' do
      loop do
        gsleep 0.1
        @@objects.values.each do |socket|
          # FIXME This isn't the right way to do this
          socket.resend_packet
        end
      end
    end

    socket.create_channel :utp

    SimpleThread.new 'utp_recv' do
      loop do
        data, addr = socket.recv_from_channel(:utp)
        handle_incoming_packet data, addr
      end
    end
  end

  def self.accept
    packet = gunlock { @@incoming.shift }

    self.new packet
  end

  def initialize *args
    raise "Not setup" unless @@socket

    # Is this incoming or outgoing?
    if args.first.is_a? Packet
      # Incoming
      packet = args.first
      @peer_addr = packet.src[3]
      @peer_port = packet.src[1]
      @conn_id_recv = packet.connection_id + 1
      @conn_id_send = packet.connection_id
      @seq_nr = rand(2**16)
      @ack_nr = packet.seq_nr
      @outbound = false
      @state = :connected
    else
      # Outgoing
      @peer_addr = args[0]
      @peer_port = args[1]
      @conn_id_recv = rand(2**16)
      @conn_id_send = @conn_id_recv + 1
      @seq_nr = 1
      @ack_nr = nil
      @outbound = true
      @state = :connecting
    end

    # FIXME make sure that "addr" is resolved to an IP address
    @client_id = "#@peer_addr:#@peer_port/#@conn_id_recv"

    # Queue for incoming data.  The thread that reads the data off the socket
    # isn't the thread that will be in the middle of a read() or gets() call.
    @queue = String.new
    @data_available = SimpleCondition.new

    # Buffer of data for BufferedIO
    @buffer = String.new

    # Receive data

    # Window of packets that are currently "in flight" to our peer.  Each
    # packet stays in this array until it we receive an ACK for it.
    @window = []

    @window_has_room = SimpleCondition.new

    @socket = @@socket

    @@objects[@client_id] = self

    if @outbound
      connect
    else
      respond_to_syn packet
    end
  end

  # FIXME temporary for debugging
  def warn msg
    @lock ||= File.open( "/tmp/lockylock", 'a' )
    @lock.flock File::LOCK_EX
    Kernel.warn "#$$ #{Thread.current.title}> #{msg}"
    @lock.flock File::LOCK_UN
  end

  def write data
    raise "Socket is closed" if @state == :closed

    while data.size > 0
      # If our window is full then we need to block.
      while window_full?
        @window_has_room.wait
      end
      packet = Packet.new
      packet.type = :data
      packet.seq_nr = (@seq_nr += 1)
      packet.ack_nr = @ack_nr
      amount = [data.size, max_packet_size].min
      packet.data = data[0...amount]
      data = data[amount..-1]

      @window << packet
      send_packet packet
    end
  end

  def close
    @state = :closed
    packet = Packet.new
    packet.type = :fin
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = @ack_nr
    packet.timestamp_diff = 0
    send_packet packet
  end

  def self.handle_incoming_packet data, addr
    # Skip STUN packets, which come in on the same socket
    return if data[4...8].unpack('N').first == 0x2112A442

    packet = Packet.parse addr, data
    client_id = "#{addr[3]}:#{addr[1]}/#{packet.connection_id}"

    if socket = @@objects[client_id]
      socket.handle_incoming_packet packet
      return true
    end

    if packet.type == :syn
      @@incoming.push packet
      return true
    end

    Log.warn "Received unexpected #{packet} from #{client_id}"
    false
  end

  # Handle all incoming packets
  def handle_incoming_packet packet
    warn "Got #{packet}"

    if @state == :connecting
      return unless packet.type == :state
      @window.shift
      @ack_nr = packet.seq_nr
      @state = :connected
      return
    end

    return if @state == :closed

    if packet.type == :fin || packet.type == :reset
      # FIXME closing should wait for other packets still
      @state = :closed
      @@objects.delete @client_id
      return
    end

    return unless packet.type == :state || packet.type == :data

    # Move window forward
    # FIXME handle seq_nr wrapping around to zero for long connections
    while @window.first && @window.first.seq_nr <= packet.ack_nr
      @window.shift
    end

    # Notify senders (if any) that the window is no longer full
    @window_has_room.signal unless window_full?

    return unless packet.type == :data

    # FIXME handle seq_nr wrapping around to zero
    if @ack_nr + 1 == packet.seq_nr
      @ack_nr = packet.seq_nr
      @queue << packet.data
      @data_available.signal
    end

    # FIXME Sending an ack for every incoming packet is inefficient.  If we
    # delay a small amount of time we can send a single ACK to ack multiple
    # packets.
    #
    # We can have the same thread that does retransmissions handle sending out
    # ACKs, since it will be a similar job.
    ack = Packet.new
    ack.type = :state
    ack.timestamp_diff = now - packet.timestamp
    ack.ack_nr = @ack_nr
    ack.seq_nr = @seq_nr
    send_packet ack
  end

  def resend_packet
    # FIXME This is temporary
    return unless @window.first
    send_packet @window.first
  end

  private

  def send_packet packet
    packet.timestamp = now
    # FIXME How do we determine our advertised window size?
    packet.wnd_size = 1000
    packet.connection_id ||= @conn_id_send
    warn "Sending #{packet}"
    @socket.send packet.to_binary, 0, @peer_addr, @peer_port
  end

  def now
    time = Time.new
    (time.to_i * 1_000_000 + time.usec) % 2**32
  end

  def max_packet_size
    900 # FIXME
  end

  def window_full?
    @window.size > 10 # FIXME
  end

  def connect
    # Send SYN packet
    packet = Packet.new
    packet.type = :syn
    packet.connection_id = @conn_id_recv
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = 0

    @window << packet
    send_packet packet

    # FIXME Don't spinlock here
    CONNECT_TIMEOUT.times do
      gsleep 1
      send_packet packet
      return if @state == :connected
    end

    raise "Connection timeout to #@peer_addr:#@peer_port"
  end

  def respond_to_syn syn
    # FIXME If this packet is dropped then the connection attempt times out
    packet = Packet.new
    packet.type = :state
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = @ack_nr
    packet.timestamp_diff = now - syn.timestamp
    send_packet packet
  end

  # Read a partial packet straight from the socket.  Don't use this, instead
  # call readpartial, read, or gets.
  def unbuffered_readpartial maxlen
    # Even though this should be unbuffered, we have to implement our own
    # incoming buffer because we can't limit the size of incoming packets.
    #
    # Luckily we can drain it immediately which keeps things simple.

    if @queue.size > 0
      amount = [@queue.size, maxlen].min
      slice = @queue[0...amount]
      @queue = @queue[amount..-1]
      warn "readpartial returning #{slice.inspect}"
      return slice
    end

    return nil if @state == :closed

    warn "Waiting for data"
    @data_available.wait

    # Since the packet might be bigger than maxlen, we'll need to split it,
    # which we can let our buffer splitter code above do if add the data to the
    # buffer and recurse.
    return unbuffered_readpartial maxlen
  end
end
