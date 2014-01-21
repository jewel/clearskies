# Manage connections with peers.  See "Connection" for more information.

require 'socket'
require_relative 'simple_thread'
require_relative 'broadcaster'
require_relative 'tracker_client'
require_relative 'unauthenticated_connection'
require_relative 'id_mapper'
require_relative 'upnp'
require_relative 'connection_manager'
require_relative 'shared_udp_socket'
require_relative 'stun_client'
require_relative 'utp_socket'

module Network
  # Start all network-related pieces.  This spawns several background threads.
  def self.start
    @connections = {}

    # Try IPv6 and if that doesn't work fall back to IPv4
    begin
      @server = UnlockingTCPServer.new '::', Conf.listen_port
    rescue Errno::EAFNOSUPPORT
      Log.warn "No IPv6 support for TCP service"
      @server = UnlockingTCPServer.new '0.0.0.0', Conf.listen_port
    end

    SimpleThread.new('network') do
      listen
    end

    Broadcaster.tcp_port = listen_port
    Broadcaster.on_peer_discovered do |share_id,peer_id,addr,port|
      Log.debug "Broadcast discovered #{share_id} #{peer_id} #{addr} #{port}"
      peer_discovered share_id, peer_id, 'tcp', addr, port
    end
    Broadcaster.start unless ENV['DISABLE_BROADCAST']

    TrackerClient.tcp_port = listen_port
    TrackerClient.on_peer_discovered do |share_id,peer_id,proto,addr,port|
      Log.debug "Tracker discovered #{share_id} #{peer_id} #{proto} #{addr} #{port}"
      peer_discovered share_id, peer_id, proto, addr, port
    end
    TrackerClient.start

    # Create shared UDP socket for both STUN and uTP
    @udp_socket = SharedUDPSocket.new
    @udp_socket.bind '0.0.0.0', Conf.udp_port

    stun_client = STUNClient.new @udp_socket
    stun_client.on_bind do |addr,port|
      TrackerClient.utp_port = port
    end

    UTPSocket.setup @udp_socket
    SimpleThread.new 'utp_accept' do
      loop do
        client = UTPSocket.accept
        start_connection client
      end
    end

    stun_client.start

    UPnP.start listen_port
  end

  # Force an immediate attempt at finding new peers, instead of waiting for the
  # next timer.
  def self.force_find_peer
    TrackerClient.force_run
    Broadcaster.force_run
  end

  private
  # Listen for incoming clearskies connections.
  def self.listen
    loop do
      client = @server.accept
      start_connection client
    end
  end

  # Current listening port.  This will be different than Conf.listen_port if
  # Conf.listen_port is set to 0.
  def self.listen_port
    @server.local_address.ip_port
  end

  # Callback for when a peer is discovered.
  def self.peer_discovered id, peer_id, proto, addr, port
    share, code = IDMapper.find id
    unless share || code
      Log.debug "Can't find ID #{id}"
      return
    end

    if (share || code).peer_id == peer_id
      Log.debug "Discovered ourself"
      return
    end

    return if ConnectionManager.have_connection? id, peer_id

    start_connection [proto, addr, port], share, code
  end

  # Start a connection, regardless of source.
  def self.start_connection *args
    connection = UnauthenticatedConnection.new *args

    ConnectionManager.connecting connection

    connection.on_authenticated do |connection|
      ConnectionManager.connected connection
    end

    connection.start

    nil
  end
end
