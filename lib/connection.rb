# Base class for both unauthenticated and authenticated connections.
#
# A connection starts out unauthenticated, goes through a handshake process,
# and then becomes an authenticated connection.
#
# This separation is arbitrary and is just to help keep Connection from having
# too much code.

require_relative 'simple_thread'
require_relative 'message'

class Connection
  attr_reader :timeout_at

  private
  def send type, opts={}
    if !type.is_a? Message
      message = Message.new type, opts
    else
      message = type
    end

    Log.debug "Sending: #{message.inspect}"
    if @send_queue
      @send_queue.push message
    else
      gunlock { message.write_to_io @socket }
    end
  end

  def start_send_thread
    @send_queue = Queue.new
    @sending_thread = SimpleThread.new 'connection_send' do
      gunlock {
        while msg = @send_queue.shift
          msg.write_to_io @socket
        end
      }
    end
  end

  def recv type=nil
    loop do
      msg = gunlock { Message.read_from_io @socket }
      return msg if !type || msg.type.to_s == type.to_s
      Log.warn "Unexpected message: #{msg[:type]}, expecting #{type}"
    end

    msg
  end
end
