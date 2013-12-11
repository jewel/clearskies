# Clearskies supports stateful connections over both TCP and UDP.  In order
# to have state in UDP we have an implementation of uTP (see UTPSocket).  We
# want to be able to use either class interchangeably, without Connection and
# friends from having to know the difference.
#
# This is not a problem except for with the global lock from SimpleThread.
# When we have code like this:
#
# gunlock { socket.gets }
#
# It means that UTPSocket needs to worry about thread safety.  Instead, it'd be
# ideal if both socket types unlocked automatically at the correct place.  In
# order to accomplish that, this class wraps TCPSocket so that it behaves like
# UTPSocket.

require 'socket'
require_relative 'simple_thread'

class UnlockingTCPServer < TCPServer
  def accept *args
    socket = gunlock { super *args }
    UnlockingTCPSocket.new socket
  end
end

# We can't inherit from TCPSocket because TCPServer#accept returns a TCPSocket
# and there's no way to cast that into becoming an UnlockingTCPSocket, so we
# wrap the class.  That's convenient because only methods supported by
# UTPSocket should be present, anyway.
class UnlockingTCPSocket
  def initialize *args
    if args.first && args.first.is_a?(TCPSocket)
      @socket = socket
    else
      @socket = gunlock { TCPSocket.new *args }
    end
  end

  def peeraddr *args
    @socket.peeraddr *args
  end

  def gets *args
    gunlock { @socket.gets *args }
  end

  def puts *args
    gunlock { @socket.puts *args }
  end

  def readpartial *args
    gunlock { @socket.readpartial *args }
  end

  def read *args
    gunlock { @socket.read *args }
  end

  def write *args
    gunlock { @socket.write *args }
  end
end
