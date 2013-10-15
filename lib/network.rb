# Manage connections with peers.  See "Peer" for more information.

require 'socket'
require 'thread'
require 'broadcaster'
require 'tracker_client'

module Network
  def self.start
    Thread.new do
      listen
    end

    Broadcaster.on_peer_discovered do |peer_id,addr,port|
      warn "Got #{peer_id} #{addr} #{port}"
    end
    Broadcaster.start

    TrackerClient.on_peer_discovered do |peer_id,addr,port|
      warn "Got #{peer_id} #{addr} #{port}"
    end
    TrackerClient.start
  end

  private
  def self.listen
    @server = TCPServer.new Conf.listen_port
  end

  def self.listen_port
    @server.port
  end
end
