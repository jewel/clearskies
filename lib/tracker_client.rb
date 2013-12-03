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
    uri.query = URI.encode_www_form({
      :id => ids,
      :tcp_port => Network.listen_port,
    })
    Log.debug "Tracking with #{uri}"
    res = gunlock { Net::HTTP.get_response uri }
    return unless res.is_a? Net::HTTPSuccess
    info = JSON.parse res.body, symbolize_names: true

    info[:others].each do |share_id,peers|
      peers.each do |peerspec|
        id, addr = peerspec.split "@"
        addr =~ /\A(\w+):(\[(.*?)\]|(.*?)):(\d+)\Z/ or raise "Invalid addr #{addr.inspect}"
        proto, ip, port = $1, $3 || $4, $5
        next unless proto == "tcp"
        @peer_discovered.call share_id, id, ip, port.to_i
      end
    end
  end
end
