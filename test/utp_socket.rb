require 'minitest/autorun'

require_relative '../lib/utp_socket'
require 'socket'

describe UTPSocket do
  before do
    # Figure out safe port before forking
    server = UDPSocket.new
    server.bind '0.0.0.0', 0
    @server_port = server.local_address.ip_port

    next if fork

    UTPSocket.setup server

    while peer = UTPSocket.accept
      while data = peer.readpartial(1024)
        peer.write data
      end
      peer.close
    end
  end

  it "can connect and send data" do
    client = UDPSocket.new
    client.bind '0.0.0.0', 0
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
end
