# A fully-authenticated connection with another peer.
#
# Authentication is done by UnauthenticatedConnection
#
# The full protocol is documented in protocol/core.md

require_relative 'connection'

class AuthenticatedConnection < Connection
  MIN_PING_INTERVAL = 60

  attr_reader :peer, :share

  # Create connection representing.  Given the Share, Peer, and an IO object
  def initialize share, peer, socket
    @share = share
    @peer = peer
    @socket = socket
  end

  # Start sending thread and begin work.  This should be called from a thread
  # that belongs to the connection.
  def start
    start_send_thread
    @ping_timeout = MIN_PING_INTERVAL

    start_ping_thread

    Log.debug "Requesting manifest"
    request_manifest
    Log.debug "Receiving messages"
    receive_messages
  end

  # Returns id of the share as string
  def share_id
    share.id
  end

  # Returns id of the peer as string
  def peer_id
    peer.id
  end

  private

  # Main receive loop
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

  # Main switch between each type of message that will come in
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
      metadata = @peer.find_file msg[:path]
      return unless metadata

      file = write_file metadata do
        gunlock {
          msg.read_binary_payload
        }
      end

      if file
        @remaining.delete_if do |f|
          f[:path] == msg[:path]
        end
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

  # Given a Share::File object, turn it into a manifest entry, ready to turn
  # into JSON
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

  # Send peer our manifest
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

  # Look at incoming manifest, determine which files are needed
  def receive_manifest msg
    @files = msg[:files]
    @remaining = []
    @files.each do |file|
      @remaining.push file if need_file? file
    end
  end

  # Process UPDATE message, see if there is action we should take immediately.
  #
  # Some care must be taken to make sure that we don't interact with "Scanner"
  # in a bad way.  Scanner doesn't update the utime unless it looks like the
  # change happened locally.  As long as we update the Share::File before we
  # actually make the change, that won't be a problem.
  def process_update msg
    metadata = @share[msg[:path]]

    if msg[:size] == 0 && !metadata
      write_file msg, String.new
      return
    end

    return unless metadata
    return if msg[:utime] <= metadata[:utime]

    if msg[:deleted]
      path = @share.full_path msg[:path]
      @share.check_path path
      File.unlink path if File.exists? path
      return
    end

    # Wait to make changes until the new file arrives if it's different.
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

  # Do we need to download the file?
  def need_file? file
    # FIXME we need to actually delete it if its deleted
    return false if file[:deleted]

    ours = @share[ file[:path] ]

    return false if file[:size] == 0

    return false if ours && file[:utime] <= ours[:utime]
    # FIXME We'd also want to skip it if there is a pending download of this
    # file from another peer with an even newer utime

    !ours || file[:sha256] != ours[:sha256]
  end

  # Ask peer for a file (we keep track of which one is next to request
  # internally)
  def request_file
    file = @remaining.sample
    return unless file
    send :get, {
      path: file[:path]
    }
  end

  # Ask peer for its latest manifest
  def request_manifest
    if @peer.manifest && @peer.manifest[:version]
      send :get_manifest, {
        version: @peer.manifest[:version]
      }
    else
      send :get_manifest
    end
  end

  # Start a thread that sends a ping every so often
  def start_ping_thread
    name = SimpleThread.current.title + "_ping"
    SimpleThread.new name do
      loop do
        gsleep @ping_timeout
        send :ping, timeout: MIN_PING_INTERVAL
      end
    end
  end

  # Write a file to the share.  `metadata` is the JSON file metadata, as
  # received.  The file contents can be given as a string, or if a block is
  # given it will be called until it yields nil.
  #
  # Care must be given to not write to the file in its real path until it's
  # ready, or Scanner will pick up on it as a local change.  To avoid this, we
  # write to a temporary file.  Also we make changes to the Share::File that's
  # relevant first.
  def write_file metadata, file_data=nil
    path = metadata[:path]
    dest = @share.full_path path
    temp = "#{File.dirname(dest)}/.#{File.basename(dest)}.#$$.#{Thread.current.object_id}.!sync"
    @share.check_path dest

    dir = File.dirname dest
    FileUtils.mkdir_p dir

    digest = Digest::SHA256.new

    File.open temp, 'wb' do |f|
      if file_data
        digest << file_data
        f.write file_data
      else
        while data = yield
          digest << data
          f.write data
        end
      end
    end

    if digest.hexdigest != metadata[:sha256]
      Log.warn "Received #{dest}, but the sha256 was wrong"
      return nil
    end

    mtime = metadata[:mtime]
    mtime = Time.at mtime[0], mtime[1] / 1000.0 + 0.0005
    File.utime Time.new, mtime, temp
    File.chmod metadata[:mode].to_i(8), temp

    file = @share[path] || Share::File.create(path)
    file.sha256 = digest.hexdigest
    file.utime = metadata[:utime]

    file.commit File.stat(temp)
    file.path = path
    @share[path] = file
    File.rename temp, dest

    file
  end
end
