# Talk with the central tracker
require 'net/http'
require 'thread'

module TrackerClient
  def self.start
    @last_run = {}
    Thread.new do
      run
    end
  end

  def self.on_peer_discovered &block
    @discovered = block
  end

  private
  def self.run
    loop do
      wait_time = 60
      Shares.each do |share|
        trackers.each do |url|
          warn "Tracking against #{url}"
          uri = URI(url)
          uri.query = URI.encode_www_form({
            :id => share.id,
            :peer => share.peer_id,
            :myport => Network.listen_port,
          })
          res = Net::HTTP.get_response uri
          warn "Tracker said #{res}"
          next unless res.is_a? Net::HTTPSuccess
          info = JSON.parse res.body, symbolize_names: true

          # FIXME we really need to wait the exact amount of time requested by
          # each tracker
          wait_time = [info[:ttl] - 1, wait_time].min

          info[:others].each do |peerspec|
            id, addr = peerspec.split "@"
            # FIXME IPv6 needs better parsing
            ip, port = addr.split ":"
            Network.peer_discovered id, ip, port.to_i
          end
        end
      end

      sleep wait_time
    end
  end

  def self.trackers
    ["http://localhost:10234"]
  end
end
