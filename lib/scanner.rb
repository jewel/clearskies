# Scans for files.  If operating system support for monitoring files is
# available, use it to check for future changes, otherwise scan occasionally.

require 'safe_thread'
require 'digest/sha2'
require 'find'
require 'securerandom'
require 'pathname'
require 'change_monitor'
require 'set'
require 'log'

module Scanner
  DELAY_MULTIPLIER = 10
  MIN_RESCAN = 60
  def self.start use_change_monitor=true
    load_change_monitor if use_change_monitor
    @hasher = SafeThread.new 'hasher' do
      work_hashes
    end

    @scanning = false
    @hash_queue = Queue.new

    @worker = SafeThread.new 'scanner' do
      work
    end
  end

  def self.add_share share
    # FIXME move this into the proper thread
    register_and_scan share
  end

  # Thread entry point
  private

  def self.work
    # TODO Lower own priority

    Log.debug "Performing first scan of the shares..."
    last_scan_start = Time.now

    Shares.each do |share|
      register_and_scan share
    end

    last_scan_time = Time.now - last_scan_start
    Log.debug "Finished first scan of the shares..."

    return if @change_monitor

    Log.debug "No change monitor.  Setting up recurring scans..."

    loop do
      next_scan_time = Time.now + [last_scan_time * DELAY_MULTIPLIER, MIN_RESCAN].max
      while Time.now < next_scan_time
        gsleep [next_scan_time - Time.now,0].max
      end

      Log.debug "Performing recurring scan of the shares..."
      last_scan_start = Time.now
      Shares.each do |share|
        register_and_scan share
      end
      last_scan_time = Time.now - last_scan_start
      Log.debug "Finished recurring scan of the shares..."
    end
  end

  # Return appropriate ChangeMonitor for platform
  def self.load_change_monitor
    @change_monitor = ChangeMonitor.find
    unless @change_monitor
      Log.warn "No suitable change monitor found"
      return
    end

    @change_monitor.on_change do |path|
      monitor_callback path
    end
  end

  def self.monitor_callback path
    Shares.each do |share|
      next unless path.start_with? share.path
      process_path share, path
    end
  end

  # An event was triggered or we scanned this path
  # either way need to decide if it is updated and
  # add it to the database.
  def self.process_path share, path, &block
    relpath = share.partial_path path
    return if relpath =~ /\.!sync\Z/

    share.check_path path

    begin
      stat = File.stat path
    rescue Errno::ENOENT
      # File was deleted!
      if share[relpath]
        Log.debug "#{relpath} was deleted"
        share[relpath].deleted = true
        share.save relpath
      end

      # Don't need to do anything if it was never seen.
      Log.debug "#{relpath} is gone, but we never knew it existed"
      return
    end

    # Monitor directories and unreadable files
    send_monitor :monitor, path

    # Recursively process path
    if stat.directory?
      Log.debug "#{relpath} is a directory"
      Dir.foreach( path ) do |filename|
        next if filename == '.' || filename == '..'
        process_path share, "#{path}/#{filename}", &block
      end
      return
    end

    # Don't want pipes, sockets, devices, directories.. etc
    # FIXME this will also skip symlinks
    unless stat.file?
      Log.warn "#{path} is not a file, skipping"
      return
    end

    unless stat.readable?
      Log.warn "File #{path} is not readable. It will be skipped..."
      return
    end

    file_touched = false # need to update utime if file is changed

    file = share[relpath] || Share::File.create(relpath)

    # If mtime or sizes are different need to regenerate hash
    if file.mtime != stat.mtime || file.size != stat.size
      Log.debug "#{relpath} has changed, needs new hash"
      file.sha256 = nil
      file.commit stat
      @hash_queue.push [share, file]
      file_touched = true

    # If only the mode has changed then just update the record.
    elsif file.mode != stat.mode.to_s(8)
      Log.debug "#{relpath} mode has changed to #{file.mode}"
      file.commit stat
      file_touched = true
    end

    if file_touched
      file.utime = Time.new.to_f
      share[relpath] = file
    else
      Log.debug "#{relpath} has not changed"
    end

    block.call relpath if block
  end

  def self.register_and_scan share
    @scanning = true
    Log.info "Doing initial scan of #{share.path}"

    known_files = Set.new(share.map { |f| f.path })
    process_path share, share.path do |relpath|
      known_files.delete relpath
    end

    # What is left over are the deleted files.
    known_files.each do |path|
      process_path share, share.full_path(path)
    end
    Log.info "Finished initial scan of #{share.path}"

  ensure
    @scanning = false
    @hasher.wakeup if @hasher
  end

  def self.work_hashes
    Shares.each do |share|
      share.each do |file|
        next if file.sha256
        @hash_queue.push [share, file]
      end
    end

    if @hash_queue.size > 0
      Log.info "Hasher has #{@hash_queue.size} files to hash"
    end

    loop do
      share, file = gunlock { @hash_queue.shift }
      next if file.sha256
      digest = Digest::SHA256.new
      Log.info "Hashing #{file.path}"

      gunlock {
        File.open share.full_path(file.path), 'rb' do |f|
          while data = f.read(1024 * 512)
            digest << data

            Thread.stop if @scanning
          end
        end
      }

      Log.debug "Hashed #{file.path} to #{digest.hexdigest}"
      file.sha256 = digest.hexdigest
      share.save file.path
    end
  end

  def self.send_monitor method, *args
    return unless @change_monitor
    @change_monitor.send method, *args
  end
end
