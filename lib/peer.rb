# Represents a connection with another peer
#
# The protocol is documented in protocol/core

require 'socket'
require 'thread'
require 'openssl'

class Peer
  attr_reader :peer_id, :access, :software, :friendly_name

  SOFTWARE = "clearskies 0.1pre"

  # Create a new Peer and begin communication with it.
  #
  # Outgoing connections will already know the share it is communicating with.
  #
  # This should be called within the context of its own thread.  All methods are
  # threadsafe.
  def initialize socket, share=nil
    @share = share
    @socket = socket

    @incoming = !share

    handshake
    receive_messages
  end

  # Attempt to make an outbound connection with a peer
  def self.connect share, ip, port
    socket = TCPSocket.connect ip, port
    self.new share, socket, false
  end

  private

  def send type, opts=nil
    if !type.is_a? Message
      message = Message.new type, opts
    else
      message = type
    end

    if @send_queue
      @send_queue.push message
    else
      message.write_to_io @socket
    end
  end

  def start_send_thread
    @send_queue = Queue.new
    @sending_thread = Thread.new { send_messages }
  end

  def recv type=nil
    msg = Message.read_from_io @socket
    if type && msg.type.to_s != type.to_s
      warn "Unexpected message: #{msg[:type]}, expecting #{type}"
      return recv type
    end

    msg
  end

  def receive_messages
    loop do
      msg = recv
      handle msg
    end
  end

  def handle msg
    case msg.type
    when :get_manifest

    when :manifest_current

    end
  end

  def send_messages
    while msg = @send_queue.shift
      msg.write_to_io @socket
    end
  end

  def handshake
    if @incoming
      send :greeting, {
        software: SOFTWARE,
        protocol: [1],
        features: []
      }
    else
      greeting = recv :greeting

      unless greeting[:protocol].member? 1
        raise "Cannot communicate with peer, peer only knows versions #{greeting[:protocol].inspect}"
      end

      send :start, {
        software: SOFTWARE,
        protocol: 1,
        features: [],
        id: share.id,
        access: share.access_level,
        peer: share.peer_id,
      }
    end

    if @incoming
      start = recv :start
      @peer_id = start[:peer]
      @access = start[:access].to_sym
      @software = start[:software]
      @share = Share.by_id start[:id]
      if !@share
        send :cannot_start
        close
      end

      @level = greatest_common_access(@access, @share[:access]),

      send :starttls, {
        peer: @share.peer_id,
        access: @level,
      }
    else
      starttls = recv :starttls
      @peer_id = starttls[:peer]
      @level = starttls[@level]
    end

    @tcp_socket = @socket

    @socket = OpenSSL::SSL::SSLSocket.new @tcp_socket, ssl_context

    start_send_thread
    send :identity, {
      name: Shares.friendly_name,
      time: Time.new.to_i,
    }

    identity = recv :identity
    @friendly_name = identity[:name]

    time_diff = identity[:time] - Time.new.to_i
    if time_diff.abs > 60
      raise "Peer clock is too far #{time_diff > 0 ? 'ahead' : 'behind'} yours (#{time_diff.abs} seconds)"
    end
  end

  def greatest_common_access l1, l2
    levels = [:unknown, :untrusted, :read_only, :read_write]
    i1 = levels.index l1
    raise "Invalid access level: #{l1.inspect}" unless i1
    i2 = levels.index l2
    raise "Invalid access level: #{l2.inspect}" unless i2
    common = [i1, i2].min
    levels[common]
  end

  def ssl_context
    context = OpenSSL::SSL::SSLContext.new
    context.key = @share.key @level
    context.ciphers = ['TLS_DHE_PSK_WITH_AES_128_CBC_SHA']
    context.tmp_dh_callback = Proc.new do
      share.tls_dh_key
    end

    context
  end
end
