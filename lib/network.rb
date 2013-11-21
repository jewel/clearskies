# Manage connections with peers.  See "Connection" for more information.

require 'socket'
require_relative 'simple_thread'
require_relative 'broadcaster'
require_relative 'tracker_client'
require_relative 'unauthenticated_connection'
require_relative 'id_mapper'
require_relative 'upnp'
require_relative 'connection_manager'

module Network
  # Start all network-related pieces.  This spawns several background threads.
  def self.start
    @connections = {}

    @server = TCPServer.new Conf.listen_port

    SimpleThread.new('network') do
      listen
    end

    Broadcaster.on_peer_discovered do |share_id,peer_id,addr,port|
      Log.debug "Broadcast discovered #{share_id} #{peer_id} #{addr} #{port}"
      peer_discovered share_id, peer_id, addr, port
    end
    Broadcaster.start

    TrackerClient.on_peer_discovered do |share_id,peer_id,addr,port|
      Log.debug "Tracker discovered #{share_id} #{peer_id} #{addr} #{port}"
      peer_discovered share_id, peer_id, addr, port
    end
    TrackerClient.start

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
      client = gunlock { @server.accept }
      start_connection client
    end
  end

  # Current listening port.  This will be different than Conf.listen_port if
  # Conf.listen_port is set to 0.
  def self.listen_port
    @server.local_address.ip_port
  end

  # Callback for when a peer is discovered.
  def self.peer_discovered id, peer_id, addr, port
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

    start_connection [addr, port], share, code
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
