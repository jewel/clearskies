# Manage connections with peers.  See "Connection" for more information.

require 'socket'
require 'simple_thread'
require 'broadcaster'
require 'tracker_client'
require 'connection'
require 'id_mapper'
require 'upnp'

module Network
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

  def self.force_find_peer
    TrackerClient.force_run
    Broadcaster.force_run
  end

  private
  def self.listen
    loop do
      client = gunlock { @server.accept }
      connection = Connection.new client
      connection.on_discover_share do |share_id,peer_id|
        @connections[share_id] ||= {}
        @connections[share_id][peer_id] = connection
      end

      connection.on_disconnect do
        @connections[share_id].delete peer_id
      end

      connection.start
    end
  end

  def self.listen_port
    @server.local_address.ip_port
  end

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

    @connections[id] ||= {}
    return if @connections[id][peer_id]

    connection = Connection.new [addr, port], share, code
    @connections[id][peer_id] = connection

    connection.on_disconnect do
      @connections[id].delete peer_id
    end

    connection.start
  end
end
