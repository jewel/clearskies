# Keep track of which peers we have connections to.
#
# This keeps track of pending outgoing connections as well.

module ConnectionManager
  def self.have_connection? share_id, peer_id
    connections = get_connections key(share_id, peer_id)
    active = false
    connections.each do |connection|
      active ||= connection.active?
    end

    active
  end

  def self.connecting connection
    add_connection key(connection), connection
    nil
  end

  def self.connected connection
    add_connection key(connection), connection
    nil
  end

  def self.disconnected connection
    remove_connection key(connection), connection
    nil
  end

  private
  def self.init key
    @connections ||= {}
    @connections[key] ||= []
  end

  def self.key *args
    if args[0].is_a? Connection
      share_id = args[0].share_id
      peer_id = args[0].peer_id
    else
      share_id, peer_id = args
    end

    "#{share_id}-#{peer_id}"
  end

  def self.get_connections key
    init key
    @connections[key].select { |connection|
      !connection.timeout_at || connection.timeout_at < Time.new
    }
  end

  def self.add_connection key, connection
    init key
    @connections[key] << connection
  end

  def self.remove_connection key, connection
    init key
    @connections[key].delete connection
  end
end
