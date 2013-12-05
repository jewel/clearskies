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
    begin
      ipv4 = bind Socket::AF_INET, '0.0.0.0'

      SimpleThread.new 'broadcast4' do
        listen ipv4
      end
    rescue
      Log.warn "Could not bind IPv4 broadcast address: #$!"
    end

    begin
      ipv6 = bind Socket::AF_INET6, '::'

      SimpleThread.new 'broadcast6' do
        listen ipv6
      end
    rescue
      Log.warn "Could not bind IPv6 broadcast address: #$!"
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
  def self.listen socket
    loop do
      json, sender = gunlock { socket.recvfrom 512 }
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
      send_broadcast Socket::AF_INET, '255.255.255.255', id, peer_id
      send_broadcast Socket::AF_INET6, 'ff02::1', id, peer_id # IPv6
    end
  end

  # Send a broadcast for the given share_id and peer_id
  def self.send_broadcast type, addr, id, peer_id
    message = {
      :name => "ClearSkiesBroadcast",
      :version => 1,
      :id => id,
      :peer => peer_id,
      :myport => Network.listen_port,
    }.to_json

    socket = UDPSocket.new type
    socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true

    gunlock { socket.send message, 0, addr, BROADCAST_PORT }
  rescue
    Log.warn "Can't send broadcast to #{addr}: #$!"
  end

  def self.bind type, addr
    socket = UDPSocket.new type
    socket.setsockopt Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true
    socket.setsockopt Socket::SOL_SOCKET, Socket::SO_BROADCAST, true
    socket.bind addr, BROADCAST_PORT
    socket
  end

end
