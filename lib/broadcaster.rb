# Send and listen for LAN broadcasts, as defined in the core protocol

require 'json'
require 'thread'
require 'socket'

module Broadcaster
  BROADCAST_PORT = 60106

  def self.on_receive &block
    @receiver = @block
  end

  def self.start
    @socket = UDPSocket.new
    @socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true
    @socket.bind '', BROADCAST_PORT

    Thread.new do
      listen
    end

    Thread.new do
      run
    end
  end

  private

  def self.listen
    loop do
      json, sender = @socket.recvfrom
      msg = JSON.parse json, symbolize_names: true
      next if msg[:name] != "ClearSkiesBroadcast"
      next if msg[:version] != 1
      Network.peer_discovered msg[:peer], sender[2], msg[:myport]
    end
  end

  def self.run
    loop do
      Shares.each do |share|
        message = {
          :name => "ClearSkiesBroadcast",
          :version => 1,
          :id => share.id,
          :peer => share.peer_id,
          :myport => Network.lan_listen_port,
        }.to_json
        @socket.send message, 0, '<broadcast>', BROADCAST_PORT
      end
      sleep 60
    end
  end
end
