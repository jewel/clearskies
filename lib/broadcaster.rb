# Send and listen for LAN broadcasts, as defined in the core protocol

require 'json'
require 'safe_thread'
require 'socket'
require 'id_mapper'

module Broadcaster
  BROADCAST_PORT = 60106

  def self.on_peer_discovered &block
    @discovered = block
  end

  def self.start
    @socket = UDPSocket.new
    @socket.setsockopt Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true
    @socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true
    @socket.bind '0.0.0.0', BROADCAST_PORT

    Log.info "Broadcaster listening on #{@socket.inspect}"

    SafeThread.new do
      listen
    end

    SafeThread.new do
      run
    end
  end

  def self.force_run
    send_all_broadcast
  end

  private

  def self.listen
    loop do
      json, sender = gunlock { @socket.recvfrom 512 }
      msg = JSON.parse json, symbolize_names: true
      Log.debug "Got message: #{json}"
      next if msg[:name] != "ClearSkiesBroadcast"
      next if msg[:version] != 1
      @discovered.call msg[:id], msg[:peer], sender[2], msg[:myport]
    end
  end

  def self.run
    loop do
      send_all_broadcast
      gsleep 60
    end
  end

  def self.send_all_broadcast
    IDMapper.each do |id,peer_id|
      send_broadcast id, peer_id
    end
  end

  def self.send_broadcast id, peer_id
    message = {
      :name => "ClearSkiesBroadcast",
      :version => 1,
      :id => id,
      :peer => peer_id,
      :myport => Network.listen_port,
    }.to_json
    socket = UDPSocket.new
    socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true

    gunlock { socket.send message, 0, '255.255.255.255', BROADCAST_PORT }
  end
end
