# Send and listen for LAN broadcasts, as defined in protocol/core.md

require 'json'
require 'socket'
require_relative 'simple_thread'
require_relative 'id_mapper'

module Broadcaster
  BROADCAST_PORT = 60106

  # Callback for whenever a peer is discovered.  The block will be given the
  # share_id, peer_id, ip address, and port of the peer as arguments
  def self.on_peer_discovered &block
    @discovered = block
  end

  # Start sending broadcasts occasionally
  def self.start
    # We make sure that we mark the socket as "REUSEADDR" so that multiple
    # copies of the software can be running at once, for testing
    @socket = UDPSocket.new
    @socket.setsockopt Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true
    @socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true
    @socket.bind '0.0.0.0', BROADCAST_PORT

    Log.info "Broadcaster listening on #{@socket.inspect}"

    SimpleThread.new 'broadcast' do
      listen
    end

    SimpleThread.new 'broadcast_send' do
      run
    end
  end

  # Force an immediate broadcast
  def self.force_run
    send_all_broadcast
  end

  private

  # Listen for broadcasts from other peers
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

  # Main loop
  def self.run
    loop do
      send_all_broadcast
      gsleep 60
    end
  end

  # Send a broadcast for each share
  def self.send_all_broadcast
    IDMapper.each do |id,peer_id|
      send_broadcast id, peer_id
    end
  end

  # Send a broadcast for the given share_id and peer_id
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
