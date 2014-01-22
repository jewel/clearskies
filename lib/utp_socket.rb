# Pure ruby implementation of the "Micro Transport Protocol", or uTP
# (http://www.bittorrent.org/beps/bep_0029.html)
#
# uTP is used to give TCP-like semantics over UDP sockets.  UDP is desireable
# because of UDP hole punching for NAT firewalls.
#
# This class mimics the behavior of the regular TCP classes in ruby, where
# possible.  Note that both peers have to connect to each other at the same
# time, so this does not have the concept of "server" and "client" in the
# traditional sense.  Instead, both sides create a "server", which will can
# spawn a new outbound connection via 'connect' or a new inbound connection via
# 'accept'.

require_relative 'simple_thread'
require_relative 'simple_condition'
require_relative 'buffered_io'
require_relative 'utp_socket/packet'
require_relative 'simple_timer'

class UTPServer
  def initialize socket
    # All packets are going to come in on a single UDP socket, so a dedicated
    # thread will divvy incoming packets out to the appropriate objects via
    # Queues.
    @utp_sockets = {}
    @incoming = Queue.new
    @socket = socket

    socket.create_channel :utp

    SimpleThread.new 'utp_recv' do
      loop do
        data, addr = socket.recv_from_channel(:utp)
        find_socket_for_packet data, addr
      end
    end
  end

  def accept
    socket = gunlock { @incoming.shift }
    Log.debug "accepted connection from #{socket.client_id}"
    @utp_sockets[socket.client_id] = socket
    socket
  end

  def connect server, port
    socket = UTPSocket.new @socket, server, port
    @utp_sockets[socket.client_id] = socket
    Log.debug "connecting to #{socket.client_id}"
    socket.start_connection
    socket
  end

  private
  def find_socket_for_packet data, addr
    # Skip STUN packets, which come in on the same socket
    return if data[4...8].unpack('N').first == 0x2112A442

    packet = UTPSocket::Packet.parse addr, data
    client_id = "#{addr[3]}:#{addr[1]}/#{packet.connection_id}"

    if socket = @utp_sockets[client_id]
      socket.handle_incoming_packet packet
      return
    end

    if packet.type == :syn
      @incoming.push UTPSocket.new(@socket, packet)
      return
    end

    Log.debug "uTP received unexpected #{packet} from #{client_id}.  Valid clients are #{@utp_sockets.keys.inspect}"
  end

end

class UTPSocket
  include BufferedIO

  CONNECT_TIMEOUT = 10

  def initialize *args
    if args.first.is_a? UDPSocket
      @socket = args.shift
    elsif self.class.class_variable_defined? :@@default_socket
      @socket = @@default_socket
    else
      raise "No UDP socket configured as default_socket"
    end

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
      @wnd_size = packet.wnd_size
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
      @wnd_size = 0
    end

    # Queue for incoming data.  The thread that reads the data off the socket
    # isn't the thread that will be in the middle of a read() or gets() call.
    @queue = String.new
    @data_available = SimpleCondition.new
    @state_change = SimpleCondition.new

    # Buffer of data for BufferedIO
    @buffer = String.new

    @reply_micro = 0
    @dup_acks = 0

    @rtt = 0
    @rtt_var = 0
    @first_packet_resent = false
    # timeout in milliseconds
    @timeout = 1000
    @prev_timer = nil

    # Window of packets that are currently "in flight" to our peer.  Each
    # packet stays in this array until it we receive an ACK for it.
    @cur_window = 0
    @window = []
    @window_reduced = SimpleCondition.new

    # Start our send window at ten packets
    @max_window = 10 * max_packet_size

    if !@outbound
      respond_to_syn packet
    end
  end

  # Most of the time, a program will only have one UDP Socket, ever.  For those
  # cases, save the programmer the trouble of having to pass the socket around.
  def self.default_socket= socket
    @@default_socket = socket
  end

  def client_id
    # FIXME make sure that "addr" is resolved to an IP address
    "#@peer_addr:#@peer_port/#@conn_id_recv"
  end

  def peeraddr
    @peer_addr
  end

  def write data
    raise "Socket is closed" if @state == :closed

    while data.size > 0
      # If window is full then we need to block.
      amount = [data.size, packet_size].min

      if @cur_window + amount > [@max_window, @wnd_size].min
        @window_reduced.wait
        next
      end

      packet = Packet.new
      packet.type = :data
      packet.seq_nr = (@seq_nr += 1)
      packet.ack_nr = @ack_nr
      packet.data = data[0...amount]
      data = data[amount..-1]

      @window << packet
      @cur_window += amount
      send_packet packet
    end
  end

  def close
    @state = :closed
    @state_change.broadcast
    packet = Packet.new
    packet.type = :fin
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = @ack_nr
    send_packet packet
  end

  # Handle all incoming packets
  def handle_incoming_packet packet
    bump_timer

    @wnd_size = packet.wnd_size
    @reply_micro = now - packet.timestamp

    if @state == :connecting
      return unless packet.type == :state
      @ack_nr = packet.seq_nr
      raise "First packet is not syn!?" if !@window.first || @window.first.type != :syn
      @window.shift
      @state = :connected
      @state_change.broadcast
      return
    end

    return if @state == :closed

    if packet.type == :fin || packet.type == :reset
      @state = :closed
      @state_change.broadcast
      # FIXME Ask our UTPServer to clean up this socket, somehow
      return
    end

    return unless packet.type == :state || packet.type == :data

    # If we receive an ACK for the packet that is right before the start of the
    # window, the first packet in the window might have been lost.
    if packet.type == :state && @window.first && @window.first.seq_nr == packet.ack_nr + 1
      @dup_acks += 1

      if @dup_acks >= 3
        # Packet must have been lost, resend
        @dup_acks = 0
        @max_window /= 2

        resend_window
      end
    end

    # Update RTT tracking when receiving a normal ACK
    if packet.type == :state && @window.first && packet.ack_nr == @window.first.seq_nr && !@first_packet_resent
      packet_rtt = (now - @window.first.timestamp) / 1_000
      # Ignore wrapped data
      if packet_rtt > 0
        delta = @rtt - packet_rtt
        @rtt_var += (delta - @rtt_var) / 4
        @rtt += (packet_rtt - @rtt) / 8
        @timeout = [@rtt + @rtt_var * 4, 500].max
      end
    end

    # Move window forward.
    #
    # Note that this can be done by a :data packet or a :state packet.
    #
    # FIXME handle seq_nr wrapping around to zero for long connections
    while @window.first && @window.first.seq_nr <= packet.ack_nr
      @cur_window -= @window.first.data.size
      @max_window += ( @window.first.data.size * 2 )
      @window.shift

      # Notify senders (if any) that the window is no longer full
      @window_reduced.signal
      @dup_acks = 0
      @first_packet_resent = false
    end

    return unless packet.type == :data

    # FIXME handle seq_nr wrapping around to zero
    if @ack_nr + 1 == packet.seq_nr
      @ack_nr = packet.seq_nr
      @queue << packet.data
      @data_available.signal
    end

    send_ack
  end

  def start_connection
    packet = Packet.new
    packet.type = :syn
    packet.connection_id = @conn_id_recv
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = 0
    packet.data = String.new

    attempt = 1

    @window << packet
    send_packet packet

    while @state == :connecting
      @state_change.wait 1.0
    end
  end


  private

  def receive_queue_max_size
    # This can be tuned lower on low-memory machines
    1024 * max_packet_size
  end

  def send_packet packet
    packet.timestamp = now
    packet.timestamp_diff = @reply_micro
    packet.wnd_size = receive_queue_max_size - @queue.size
    packet.connection_id ||= @conn_id_send
    @socket.send packet.to_binary, 0, @peer_addr, @peer_port
    bump_timer
  end

  # Current timestamp, as the number of microseconds that fit in a 32 bit int
  def now
    time = Time.new
    (time.to_i * 1_000_000 + time.usec) % 2**32
  end

  def max_packet_size
    # Conservative value to avoid fragmentation
    1300
  end

  def packet_size
    # Spec calls to vary the packet size based on the send rate, but doesn't
    # give a formula.
    #
    # Since we don't measure the send rate, we'll just use the max_packet_size.
    max_packet_size
  end

  def respond_to_syn syn
    # FIXME If this packet is dropped then the connection attempt times out
    packet = Packet.new
    packet.type = :state
    packet.seq_nr = (@seq_nr += 1)
    packet.ack_nr = @ack_nr
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
      return slice
    end

    return nil if @state == :closed

    @data_available.wait

    # Since the packet might be bigger than maxlen, we'll need to split it,
    # which we can let our buffer splitter code above do if add the data to the
    # buffer and recurse.
    return unbuffered_readpartial maxlen
  end

  def send_ack
    ack = Packet.new
    ack.type = :state
    ack.ack_nr = @ack_nr
    ack.seq_nr = @seq_nr
    send_packet ack
  end

  def resend_window
    @first_packet_resent = true

    # FIXME it seems like just resending the first packet isn't enough to
    # get the stream to start flowing again.  We'll receive an immediate
    # ACK, and then will just wait until timeout to send the rest of the
    # window
    #
    # Since we don't have selective ACK yet, we'll resend
    # up to max_window of our packets again
    total = 0
    @window.each do |packet|
      send_packet packet
      total += packet.data.size
      break if total > @max_window
    end
  end

  def bump_timer
    SimpleTimer.cancel @prev_timer if @prev_timer

    run_time = Time.new + @timeout.to_f / 1000

    @prev_timer = SimpleTimer.run_at run_time do
      @max_window = packet_size
      @timeout *= 2

      # Signal that we need more data by sending ack three times
      if @state == :connected
        send_ack
        send_ack
        send_ack
      end

      resend_window
    end
  end
end
