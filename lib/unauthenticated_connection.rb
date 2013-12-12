# Represents a connection with an unknown peer.
#
# See protocol/core.md for details on the handshake protocol.
#
# Once the handshake has taken place, we hand off the connection to
# `Connection`.

require_relative 'unlocking_tcp_socket'
require_relative 'simple_thread'
require_relative 'gnutls'
require_relative 'conf'
require_relative 'id_mapper'
require_relative 'message'
require_relative 'connection'
require_relative 'authenticated_connection'

class UnauthenticatedConnection < Connection
  # Outgoing connections will already know the share or code it is
  # communicating about, but incoming connections know nothing until the
  # handshake is complete.
  def initialize socket, share=nil, code=nil
    @@counter ||= 0
    @@counter += 1
    @connection_number = @@counter

    @share = share
    @code = code
    @socket = socket

    @incoming = !share && !code
    Log.info "New #{@incoming ? 'incoming' : 'outgoing'} connection with #{peeraddr}"

    @timeout_at = Time.new + 20
  end

  # Get the ID of the share associated with this connection
  def share_id
    return nil if !@share && !@code
    (@share || @code).id
  end

  # Get the peer's ID
  def peer_id
    return nil if !@share && !@code
    (@share || @code).peer_id
  end

  # Start the connection by launching a thread for the connection.  For
  # outgoing connections this will open a socket.
  def start
    thread_name = "connection#{@connection_number > 1 ? @connection_number : nil}"

    SimpleThread.new thread_name do
      if @socket.is_a? Array
        Log.debug "Opening socket to #{@socket[0]} #{@socket[1]} #{@socket[2]}"
        proto = @socket.shift
        begin
          case proto
          when "tcp"
            @socket = UnlockingTCPSocket.new *@socket
          when "utp"
            @socket = UTPSocket.new *@socket
          else
            Log.warn "Unsupported protocol: #{proto.inspect}"
            next
          end
        rescue
          Log.warn "Could not connect via #{proto} to #{@socket.join ':'}: #$!"
          next
        end
      end

      Log.debug "Shaking hands"
      handshake

      authenticated
    end
  end

  # Once authenticated, call the given block with the peer's share_id and
  # peer_id.
  def on_authenticated &block
    @on_authenticated = block
  end

  private

  # Run the handshake, as documented in the protocol.
  def handshake
    do_greeting
    do_start
    do_starttls
    start_encryption
    do_keys if @code
    do_identity

    # We now trust that the peer_id was right, since we couldn't have received
    # the encrypted :identity message otherwise
    @share.each_peer do |peer|
      @peer = peer if peer.id == @peer_id
    end

    unless @peer
      @peer = Peer.new
      @peer.id = @peer_id
      @share.add_peer @peer
    end

    @peer.friendly_name = @friendly_name
  end

  # Send or receive the GREETING message
  def do_greeting
    if @incoming
      send :greeting, {
        software: Conf.version,
        protocol: [1],
        features: []
      }
    else
      greeting = recv :greeting

      unless greeting[:protocol].member? 1
        raise "Cannot communicate with peer, peer only knows versions #{greeting[:protocol].inspect}"
      end
    end
  end

  # Send or receive the START message
  def do_start
    if !@incoming
      send :start, {
        software: Conf.version,
        protocol: 1,
        features: [],
        id: (@code || @share).id,
        access: (@code || @share).access_level,
        peer: my_peer_id,
      }
    else
      start = recv :start
      @peer_id = start[:peer]
      @access = start[:access].to_sym
      @share, @code = IDMapper.find start[:id]
      if !@share && !@code
        send :cannot_start
        close
      end
    end
  end

  # Send or receive the STARTTLS message
  def do_starttls
    if @incoming
      if @share
        @level = greatest_common_access(@access, @share.access_level)
      else
        @level = :unknown
      end

      send :starttls, {
        peer: (@share || @code).peer_id,
        access: @level,
      }
    else
      starttls = recv :starttls
      @peer_id = starttls[:peer]
      @level = starttls[:access].to_sym
    end
  end

  # Start up the encryption layer, replacing the unencrypted socket with an
  # encrypted one.
  def start_encryption
    @tcp_socket = @socket

    psk = (@code || @share).key :psk, @level

    if ENV['NO_ENCRYPTION']
      # For testing, perhaps because GnuTLS isn't available
      @socket = @tcp_socket

      if @incoming
        send :fake_tls_handshake, key: Base64.encode64(psk)
      else
        fake = recv :fake_tls_handshake
        raise "Invalid PSK: #{fake.inspect}" unless Base64.decode64(fake[:key])== psk
      end
    else
      @socket = if @incoming
                  GnuTLS::Server.new @socket, psk
                else
                  GnuTLS::Socket.new @socket, psk
                end
    end
  end

  # Send or receive the KEYS message, or the first-time key exchange.
  def do_keys
    if @share
      # FIXME This should take the intended access level of the code into account

      send :keys, {
        access: @share.access_level,
        share_id: @share.id,
        untrusted: {
          psk: @share.key( :psk, :untrusted ),
        },
        read_only: {
          psk: @share.key( :psk, :read_only ),
          rsa: @share.key( :rsa, :read_only ),
        },
        read_write: {
          psk: @share.key( :psk, :read_write ),
          rsa: @share.key( :rsa, :read_write ),
        },
      }
      Log.debug "Sent key exchange"
      recv :keys_acknowledgment
      @share.delete_code @code
    else
      msg = recv :keys
      if share = Shares.find_by_id(msg[:share_id])
        if share.path != @code.path
          Log.warn "#{share.path} and #{@code.path} have the same share_id"
          share = nil
        else
          Log.warn "Doing key_exchange again for an existing share #{share.path}"
        end
      end

      share ||= Share.new msg[:share_id]
      @share = share

      share.path = @code.path
      share.peer_id = @code.peer_id

      share.access_level = msg[:access_level]
      share.set_key :rsa, :read_write, msg[:read_write][:rsa]
      share.set_key :rsa, :read_only, msg[:read_only][:rsa]

      share.set_key :psk, :read_write, msg[:read_write][:psk]
      share.set_key :psk, :read_only, msg[:read_only][:psk]
      share.set_key :psk, :untrusted, msg[:untrusted][:psk]

      Shares.add share

      PendingCodes.delete @code

      Log.debug "New share created"
      send :keys_acknowledgment
    end
  end

  # send and receive the IDENTITY message, as done by both sides simultaneously
  def do_identity
    send :identity, {
      name: Conf.friendly_name,
      time: Time.new.to_i,
    }

    identity = recv :identity
    @friendly_name = identity[:name]

    check_time identity[:time]
  end

  # Determine most-privileged access level shared by both peers
  def greatest_common_access l1, l2
    levels = [:unknown, :untrusted, :read_only, :read_write]
    i1 = levels.index l1
    raise "Invalid access level: #{l1.inspect}" unless i1
    i2 = levels.index l2
    raise "Invalid access level: #{l2.inspect}" unless i2
    common = [i1, i2].min
    levels[common]
  end

  # Get our peer ID instead of peer's ID.
  def my_peer_id
    if @share
      @share.peer_id
    else
      @code.peer_id
    end
  end

  # Get socket address
  def peeraddr
    if @socket.respond_to? :peeraddr
      @socket.peeraddr[2]
    else
      @socket[1]
    end
  end

  # Make sure that time mismatch between peer and us isn't too far.
  def check_time other_time
    time_diff = other_time - Time.new.to_i
    if time_diff.abs > 60
      raise "Peer clock is too far #{time_diff > 0 ? 'ahead' : 'behind'} yours (#{time_diff.abs} seconds)"
    end
  end

  # Start up AuthenticatedConnection code once authenticated.
  def authenticated
    connection = AuthenticatedConnection.new @share, @peer, @socket

    @on_authenticated.call connection if @on_authenticated

    connection.start
  end
end
