# Keep track of which peers we have connections to.
#
# This keeps track of pending outgoing connections as well.

module ConnectionManager
  # Check if we're currently connected to a peer
  def self.have_connection? share_id, peer_id
    connections = get_connections key(share_id, peer_id)
    connections.each do |connection|
      return true if connection.authenticated?
    end
    
    return false
  end

  # Call this to tell the connection manager that we are attempting to connect
  # to a peer, but haven't connected yet
  def self.connecting connection
    add_connection key(connection), connection
    nil
  end

  # Call this once connected to a peer
  def self.connected connection
    add_connection key(connection), connection
    nil
  end

  # Call this if disconnected from a peer
  def self.disconnected connection
    remove_connection key(connection), connection
    nil
  end

  private
  # Initialize some internal data structures for a given key
  def self.init key
    @connections ||= {}
    @connections[key] ||= []
  end

  # Given a share_id and peer_id (or a connection object), get a unique key
  # that uniquely represents this peer
  def self.key *args
    if args[0].is_a? Connection
      share_id = args[0].share_id
      peer_id = args[0].peer_id
    else
      share_id, peer_id = args
    end

    "#{share_id}-#{peer_id}"
  end

  # Returns list of all active connections to a peer
  def self.get_connections key
    init key
    @connections[key].select { |connection|
      !connection.timeout_at || connection.timeout_at < Time.new
    }
  end

  # Add a connection to the internal list
  def self.add_connection key, connection
    init key
    @connections[key] << connection
  end

  # Remove a connection from the internal list
  def self.remove_connection key, connection
    init key
    @connections[key].delete connection
  end
end
