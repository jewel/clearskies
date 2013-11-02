# Talk with the central tracker
require 'net/http'
require 'simple_thread'
require 'pending_codes'
require 'id_mapper'

module TrackerClient
  def self.start
    @last_run = {}
    SimpleThread.new 'tracker' do
      work
    end
  end

  def self.on_peer_discovered &block
    @peer_discovered = block
  end

  def self.force_run
    SimpleThread.new 'force_tracker' do
      poll_all_trackers
    end
  end

  private
  def self.work
    loop do
      # FIXME we really need to wait the exact amount of time requested by
      # each tracker
      wait_time = 30
      poll_all_trackers

      gsleep wait_time
    end
  end

  def self.poll_all_trackers
    IDMapper.each do |share_id,peer_id|
      trackers.each do |url|
        poll_tracker share_id, peer_id, url
      end
    end
  end

  def self.poll_tracker share_id, peer_id, url
    uri = URI(url)
    uri.query = URI.encode_www_form({
      :id => share_id,
      :peer => peer_id,
      :myport => Network.listen_port,
    })
    Log.debug "Tracking with #{uri}"
    res = gunlock { Net::HTTP.get_response uri }
    return unless res.is_a? Net::HTTPSuccess
    info = JSON.parse res.body, symbolize_names: true

    info[:others].each do |peerspec|
      id, addr = peerspec.split "@"
      # FIXME IPv6 needs better parsing
      ip, port = addr.split ":"
      @peer_discovered.call share_id, id, ip, port.to_i
    end
  end

  def self.trackers
    ["http://clearskies.tuxng.com/clearskies/track"]
  end
end
