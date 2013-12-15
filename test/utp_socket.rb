require 'minitest/autorun'

require_relative '../lib/utp_socket'
require_relative '../lib/shared_udp_socket'
require 'socket'

if $0 == __FILE__
  Log.screen_level = :debug
end

class LossyUDPSocket < SharedUDPSocket
  def initialize *args
    @start = Time.new
    @total = 0
    super *args
  end

  def send *args
    # Rate limit to 3 KB/s
    @total += args[0].size
    rate = @total.to_f / (Time.new - @start)
    return if rate > 3000

    # Drop some packets no matter what
    return if rand(100) == 0

    # Duplicate others
    super *args if rand(100) == 0

    super *args
  end

  def recvfrom *args
    # Drop some packets
    if rand(4) == 0
      glock {
        Log.warn "Dropping"
      }
      super *args
    end

    # Duplicate others
    if @prev_packet && rand(4) == 0
      glock {
        Log.warn "Duplicating"
      }
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
    server.close

    @server_pid = fork
    next if @server_pid

    server = SharedUDPSocket.new
    server.bind '127.0.0.1', @server_port

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
    client = SharedUDPSocket.new
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

    # Non-chatty test
    100.times do |i|
      str = "#{i} " * i
      peer.write str
    end

    100.times do |i|
      str = "#{i} " * i
      peer.read(str.size).must_equal str
    end

    # Chatty test
    100.times do |i|
      str = "#{i} " * i
      peer.write str
      peer.read(str.size).must_equal str
    end
    peer.close
  end
end
