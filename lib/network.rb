# Manage connections with peers.  See "Peer" for more information.

require 'socket'
require 'thread'
require 'broadcaster'

module Network
  def self.start
    Thread.new do
      listen
    end
    Broadcaster.on_receive do |peer_id,addr,port|
      puts "Got #{peer_id} #{addr} #{port}"
    end
    Broadcaster.start
  end

  private
  def self.listen
    @server = TCPServer.new Conf.listen_port
  end

  def self.listen_port
    @server.port
  end
end
