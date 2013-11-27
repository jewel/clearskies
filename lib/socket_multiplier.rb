# Wrapper around a UDP Socket so that multiple objects can subscribe to its
# incoming messages
#
# This is necessary because both STUN and uTP will be using the same socket.

require 'simple_thread'

class SocketMultiplier
  def self.setup socket
    return if @setup
    @socket = socket
    @callbacks = []

    SimpleThread.new 'socket_mult' do
      loop do
        receive_packet
      end
    end

    @setup = true
  end

  def self.on_recvfrom priority, &block
    @callbacks[priority] = block
  end

  private
  def self.receive_packet
    data, addr = @socket.recvfrom
    @callbacks.each do |callback|
      res = callback.call data, addr
      break if res
    end
  end
end
