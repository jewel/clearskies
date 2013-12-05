require 'minitest/autorun'

require_relative '../lib/utp_socket'
require 'socket'

class LossyUDPSocket < UDPSocket
  def send *args
    # Drop some packets
    return if rand(4) == 0

    # Duplicate others
    super *args if rand(4) == 0

    super *args
  end

  def recvfrom *args
    # Drop some packets
    if rand(4) == 0
      warn "Dropping"
      super *args
    end

    # Duplicate others
    if @prev_packet && rand(4) == 0
      warn "Duplicating"
      return @prev_packet
    end

    @prev_packet = super *args
    @prev_packet
  end
end

describe UTPSocket do
  before do
    server = UDPSocket.new
    server.bind '127.0.0.1', 0
    @server_port = server.local_address.ip_port

    @server_pid = fork
    next if @server_pid

    UTPSocket.setup server
    while peer = UTPSocket.accept
      while data = peer.readpartial(1024)
        peer.write data
      end
      peer.close
    end
    exit
  end

  after do
    Process.kill :TERM, @server_pid
  end

  it "can connect and send data" do
    client = UDPSocket.new
    client.bind '127.0.0.1', 0
    UTPSocket.setup client

    peer = UTPSocket.new '127.0.0.1', @server_port
    peer.puts "hehe"
    peer.gets.must_equal "hehe\n"
    peer.puts "hoheho 1234"
    peer.gets.must_equal "hoheho 1234\n"
    100.times do |i|
      str = "!" * i
      peer.write str
      peer.read(i).must_equal str
    end
    peer.close
  end

  it "can handle high packet loss" do
    client = LossyUDPSocket.new
    client.bind '127.0.0.1', 0
    UTPSocket.setup client

    peer = UTPSocket.new '127.0.0.1', @server_port
    peer.puts "greetings!"
    peer.gets.must_equal "greetings!\n"

    100.times do |i|
      str = "#{i} " * i
      peer.write str
      peer.read(str.size).must_equal str
    end
    peer.close
  end
end
