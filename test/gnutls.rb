require 'minitest/autorun'
require_relative '../lib/gnutls'

def run_test first_tls_class, second_tls_class
  before do
    server = TCPServer.new "localhost", 0
    @port = server.local_address.ip_port

    next if fork
    begin
      loop do
        socket = server.accept
        if fork
          socket.close
          next
        end
        begin
          tls = first_tls_class.new socket, "abcd"
          while data = tls.readpartial(1024)
            tls.write data
          end
        rescue EOFError
        rescue
          warn "Helper process raised exception: #$!"
        end
        exit
      end
    rescue
      warn "Helper process raised exception: #$!"
    end
    exit
  end

  it "can connect and send data" do
    socket = TCPSocket.new "localhost", @port
    tls = second_tls_class.new socket, "abcd"
    tls.puts "hehe"
    tls.gets.must_equal "hehe\n"
    tls.puts "hoheho 1234"
    tls.gets.must_equal "hoheho 1234\n"
    1000.times do |i|
      str = "!" * 1024
      tls.write str
      tls.read(1024).must_equal str
    end
  end

  it "won't connect with wrong password" do
    socket = TCPSocket.new "localhost", @port
    proc {
      tls = second_tls_class.new socket, "1234"
    }.must_raise GnuTLS::Error
  end
end

describe GnuTLS::Session do
  describe "acts as a server" do
    run_test GnuTLS::Socket, GnuTLS::Server
  end

  describe "acts as a client" do
    run_test GnuTLS::Server, GnuTLS::Socket
  end
end

