# Represents a fully-authenticated connection with another peer.
#
# Authentication is done by UnauthenticatedConnection
#
# The full protocol is documented in protocol/core.md

require_relative 'connection'

class AuthenticatedConnection < Connection
  MIN_PING_INTERVAL = 60

  attr_reader :peer, :share

  def initialize share, peer, socket
    @share = share
    @peer = peer
    @socket = socket
  end

  def start
    start_send_thread
    @ping_timeout = MIN_PING_INTERVAL

    start_ping_thread

    Log.debug "Requesting manifest"
    request_manifest
    Log.debug "Receiving messages"
    receive_messages
  end

  def share_id
    share.id
  end

  def peer_id
    peer.id
  end

  private

  def receive_messages
    loop do
      msg = recv
      @timeout_at = Time.new + (@ping_timeout * 1.1)
      Log.debug "Received: #{msg.to_s}"
      begin
        handle msg
      rescue
        Log.error "Error handling message #{msg[:type].inspect}: #$!"
        $!.backtrace.each do |line|
          Log.error line
        end
      end
    end
  end

  def handle msg
    case msg.type
    when :ping
      @ping_timeout = [msg[:timeout], MIN_PING_INTERVAL].max

    when :get_manifest
      if msg[:version] && msg[:version] == @share.version
        send :manifest_current
        return
      end
      send_manifest
      @share.subscribe do |file|
        Log.debug "Learned about a change to #{file.path}"
        send_update file
      end
    when :manifest_current
      receive_manifest @peer.manifest
      request_file
    when :manifest
      # FIXME this isn't being saved
      @peer.manifest = msg
      @peer.updates = []
      receive_manifest msg
      msg[:files].each do |file|
        process_update file
      end
      request_file
    when :update
      @peer.updates << msg
      process_update msg[:file]
      @remaining.push msg[:file] if need_file? msg[:file]
      request_file
    when :move
      raise "Move not yet handled"
    when :get
      fp = @share.open_file msg[:path], 'rb'
      res = Message.new :file_data, { path: msg[:path] }
      remaining = fp.size
      if msg[:range]
        fp.pos = msg[:range][0]
        res[:range] = msg[:range]
        remaining = msg[:range][1]
      end

      res.binary_payload do
        if remaining > 0
          data = fp.read [1024 * 256, remaining].max
          remaining -= data.size
          data
        else
          fp.close
          nil
        end
      end

      send res
    when :file_data
      dest = @share.full_path msg[:path]
      temp = "#{File.dirname(dest)}/.#{File.basename(dest)}.#$$.#{Thread.current.object_id}.!sync"

      metadata = @peer.find_file msg[:path]
      return unless metadata

      @share.check_path dest

      dir = File.dirname dest
      FileUtils.mkdir_p dir

      digest = Digest::SHA256.new
      File.open temp, 'wb' do |f|
        gunlock {
          while data = msg.read_binary_payload
            digest << data
            f.write data
          end
        }
      end

      if digest.hexdigest != metadata[:sha256]
        Log.warn "Received #{dest}, but the sha256 was wrong"
        return
      end

      mtime = metadata[:mtime]
      mtime = Time.at mtime[0], mtime[1] / 1000.0 + 0.0005
      File.utime Time.new, mtime, temp
      File.chmod metadata[:mode].to_i(8), temp

      file = @share[msg[:path]] || Share::File.create(msg[:path])
      file.sha256 = digest.hexdigest
      file.utime = metadata[:utime]

      file.commit File.stat(temp)
      file.path = msg[:path]
      @share[msg[:path]] = file
      File.rename temp, dest

      @remaining.delete_if do |file|
        file[:path] == msg[:path]
      end

      request_file
    end
  end

  def send_update file
    return unless file.sha256
    send :update, {
      file: file_as_manifest(file),
    }
  end

  def file_as_manifest file
    if file[:deleted]
      obj = {
        path: file.path,
        utime: file.utime,
        deleted: true,
        id: file.id
      }
    else
      obj = {
        path: file.path,
        utime: file.utime,
        size: file.size,
        mtime: file.mtime,
        mode: file.mode,
        sha256: file.sha256,
        id: file.id,
        key: file.key,
      }
    end
  end

  def send_manifest
    msg = Message.new :manifest
    msg[:peer] = @share.peer_id
    msg[:version] = @share.version
    msg[:files] = []
    @share.each do |file|
      next unless file[:sha256]

      obj = file_as_manifest file

      msg[:files] << obj
    end

    send msg
  end

  def receive_manifest msg
    @files = msg[:files]
    @remaining = []
    @files.each do |file|
      @remaining.push file if need_file? file
    end
  end

  def process_update msg
    metadata = @share[msg[:path]]

    return unless metadata
    return if msg[:utime] <= metadata[:utime]

    if msg[:deleted]
      path = @share.full_path msg[:path]
      @share.check_path path
      File.unlink path if File.exists? path
      return
    end

    return if msg[:sha256] != metadata[:sha256]

    time_match = msg[:mtime] == metadata[:mtime]

    if !time_match
      path = @share.full_path msg[:path]
      @share.check_path path

      # Update the metadata to match before changing the mtime
      metadata[:mtime] = msg[:mtime]
    end

    mode_match = msg[:mode] == metadata[:mode]

    if !mode_match
      path = @share.full_path msg[:path]
      @share.check_path path

      # Update the metadata to match before doing the chmod
      # to prevent endless chmod loops between peers
      metadata[:mode] = msg[:mode]
    end

    if !time_match || !mode_match
      metadata[:utime] = msg[:utime]
      @share.save msg[:path]
    end

    if !time_match
      mtime = msg[:mtime]
      mtime = Time.at mtime[0], mtime[1] / 1000.0 + 0.0005
      File.utime Time.new, mtime, path
    end

    if !mode_match
      File.chmod metadata[:mode].to_i(8), path
    end
  end

  def need_file? file
    # FIXME we need to actually delete it if its deleted
    return false if file[:deleted]

    ours = @share[ file[:path] ]

    return false if ours && file[:utime] <= ours[:utime]
    # FIXME We'd also want to skip it if there is a pending download of this
    # file from another peer with an even newer utime

    !ours || file[:sha256] != ours[:sha256]
  end

  def request_file
    file = @remaining.sample
    return unless file
    send :get, {
      path: file[:path]
    }
  end

  def request_manifest
    if @peer.manifest && @peer.manifest[:version]
      send :get_manifest, {
        version: @peer.manifest[:version]
      }
    else
      send :get_manifest
    end
  end

  def start_ping_thread
    name = SimpleThread.current.title + "_ping"
    SimpleThread.new name do
      loop do
        gsleep @ping_timeout
        send :ping, timeout: MIN_PING_INTERVAL
      end
    end
  end
end
