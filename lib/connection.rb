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
  # Send message of `type` to peer.
  #
  # First argument can also be a pre-built Message object.
  #
  # This will be sent later if the `send_thread` has been started, otherwise it
  # will be sent immediately
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

  # Start a background thread to send messages to the peer
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

  # Receive the next message from peer.  This is a blocking call.  If `type` is
  # given, keep receiving messages until a message with a matching type is
  # received.
  def recv type=nil
    loop do
      msg = gunlock { Message.read_from_io @socket }
      return msg if !type || msg.type.to_s == type.to_s
      Log.warn "Unexpected message: #{msg[:type]}, expecting #{type}"
    end

    msg
  end
end
