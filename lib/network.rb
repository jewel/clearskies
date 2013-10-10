# Manage connections with peers.  See "Peer" for more information.

require 'socket'
require 'thread'

module Network
  def self.start
    Thread.new do
      listen
    end
  end

  private
  def self.listen
    @server = TCPServer.new Conf.listen_port
  end

  def self.listen_port
    @server.port
  end
end
