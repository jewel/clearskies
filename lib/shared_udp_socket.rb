# Shared UDP socket.
#
# This is necessary because both STUN and uTP will be using the same socket.

require 'socket'
require_relative 'simple_thread'

class SharedUDPSocket < UDPSocket
  def initialize *args
    @channels = {}
    super *args
    SimpleThread.new 'shared_udp' do
      loop do
        receive_packet
      end
    end
  end

  # Create a named channel
  def create_channel name
    @channels[name] = Queue.new
  end

  # Receive a packet.  Use this instead of recvfrom.
  # Returns data, addr
  def recv_from_channel name
    raise "No such channel #{name.inspect}" unless queue = @channels[name]
    gunlock { return queue.shift }
  end

  private
  def receive_packet
    data, addr = gunlock { recvfrom 65535 }

    @channels.each do |name,queue|
      queue.push [data, addr]
    end
  end
end
