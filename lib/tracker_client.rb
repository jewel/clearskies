# Talk with a central tracker.

require 'net/http'
require_relative 'simple_thread'
require_relative 'pending_codes'
require_relative 'id_mapper'

module TrackerClient
  # Start background thread
  def self.start
    @last_run = {}
    SimpleThread.new 'tracker' do
      work
    end
  end

  def self.utp_port= val
    @utp_port = val
  end

  def self.tcp_port= val
    @tcp_port = val
  end

  # Callback for when peer is discovered
  def self.on_peer_discovered &block
    @peer_discovered = block
  end

  # Force connection to tracker
  def self.force_run
    SimpleThread.new 'force_tracker' do
      poll_all_trackers
    end
  end

  private
  # Main thread entry point
  def self.work
    loop do
      # FIXME we really need to wait the exact amount of time requested by
      # each tracker
      wait_time = 30
      poll_all_trackers

      gsleep wait_time
    end
  end

  # Ask all trackers for information about all of our shares.
  def self.poll_all_trackers
    Conf.trackers.each do |url|
      ids = []
      IDMapper.each do |share_id,peer_id|
        ids << "#{share_id}@#{peer_id}"
      end
      next if ids.empty?
      poll_tracker ids, url
    end
  end

  # Ask tracker for a list of peers interested in a share.
  def self.poll_tracker ids, url
    uri = URI(url)
    query = {
      :id => ids,
    }

    query[:tcp_port] = @tcp_port if @tcp_port
    query[:utp_port] = @utp_port if @utp_port

    uri.query = URI.encode_www_form(query)
    Log.debug "Tracking with #{uri}"
    res = gunlock { Net::HTTP.get_response uri }
    return unless res.is_a? Net::HTTPSuccess
    info = JSON.parse res.body, symbolize_names: true

    info[:others].each do |share_id,peers|
      share_id = share_id.to_s
      peers.each do |peerspec|
        id, addr = peerspec.split "@"
        addr =~ /\A(\w+):(\[(.*?)\]|(.*?)):(\d+)\Z/ or raise "Invalid addr #{addr.inspect}"
        proto, ip, port = $1, $3 || $4, $5
        @peer_discovered.call share_id, id, proto, ip, port.to_i
      end
    end
  end
end
