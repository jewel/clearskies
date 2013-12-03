# Wrapper around a UDP Socket so that multiple objects can subscribe to its
# incoming messages
#
# This is necessary because both STUN and uTP will be using the same socket.

require_relative 'simple_thread'

class SocketMultiplier
  PRIORITIES = [:low, :medium, :high]

  def self.setup socket
    raise "Already setup, but with a different socket" if @setup and socket != @socket
    return if @setup
    @socket = socket
    @callbacks = {}

    SimpleThread.new 'socket_mult' do
      loop do
        receive_packet
      end
    end

    @setup = true
  end

  def self.on_recvfrom priority, &block
    @callbacks[priority] ||= []
    @callbacks[priority] << block
  end

  private
  def self.receive_packet
    data, addr = gunlock { @socket.recvfrom 65535 }
    PRIORITIES.each do |priority|
      callbacks = @callbacks[priority] || []
      callbacks.each do |callback|
        res = callback.call data, addr
        break if res
      end
    end
  end
end
