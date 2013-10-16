# Manage connections with peers.  See "Connection" for more information.

require 'socket'
require 'thread'
require 'broadcaster'
require 'tracker_client'
require 'connection'

module Network
  def self.start
    @connections = {}
    Thread.new do
      listen
    end

    Broadcaster.on_peer_discovered do |share_id,peer_id,addr,port|
      warn "Broadcast discovered #{share_id} #{peer_id} #{addr} #{port}"
      peer_discovered share_id, peer_id, addr, port
    end
    Broadcaster.start

    TrackerClient.on_peer_discovered do |share_id,peer_id,addr,port|
      warn "Tracker discovered #{share_id} #{peer_id} #{addr} #{port}"
      peer_discovered share_id, peer_id, addr, port
    end
    TrackerClient.start
  end

  private
  def self.listen
    @server = TCPServer.new Conf.listen_port

    loop do
      client = @server.accept
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
    Conf.listen_port
  end

  def self.peer_discovered share_id, peer_id, addr, port
    share = Shares.by_id share_id
    # FIXME need to look up access codes here
    raise "We don't have share #{share_id}" unless share

    @connections[share_id] ||= {}
    p @connections
    return if @connections[share_id][peer_id]

    connection = Connection.connect share, addr, port
    @connections[share_id][peer_id] = connection

    connection.on_disconnect do
      @connections[share_id].delete peer_id
    end

    connection.start
  end
end
