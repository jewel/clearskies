require 'minitest/autorun'

require_relative '../lib/utp_socket'
require 'socket'

describe UTPSocket do
  before do
    # Figure out safe port before forking
    server = UDPSocket.new
    server.bind '0.0.0.0', 0
    @server_port = server.local_address.ip_port

    @client_socket = UDPSocket.new
    @client_socket.bind '0.0.0.0', 0
    @client_port = @client_socket.local_address.ip_port

    next if fork

    STDOUT.reopen "/dev/null"
    STDERR.reopen "/dev/null"

    @client_socket.close

    UTPSocket.setup server

    peer = UTPSocket.new '127.0.0.1', @client_port

    while data = peer.readpartial(1024)
      peer.write data
    end

    peer.close
  end

  it "can connect and send data" do
    UTPSocket.setup @client_socket
    peer = UTPSocket.new '127.0.0.1', @server_port
    peer.puts "hehe"
    peer.gets.must_equal "hehe\n"
    peer.puts "hoheho 1234"
    peer.gets.must_equal "hoheho 1234\n"
    1000.times do |i|
      str = "!" * 1024
      peer.write str
      peer.read(1024).must_equal str
    end
    peer.close
  end
end
