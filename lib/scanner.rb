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
    @hasher = SafeThread.new { work_hashes }

    @scanning = false
    @hash_queue = Queue.new

    @worker = SafeThread.new { work }
  end

  def self.add_share share
    # FIXME move this into the proper thread
    register_and_scan share
  end

  # Thread entry point
  private

  def self.work
    # TODO Lower own priority

    last_scan_start = Time.now

    Shares.each do |share|
      register_and_scan share
    end

    last_scan_time = Time.now - last_scan_start

    return if @change_monitor

    loop do
      next_scan_time = Time.now + [last_scan_time * DELAY_MULTIPLIER, MIN_RESCAN].max
      now = Time.now
      while now < next_scan_time
        gsleep next_scan_time - now
      end

      last_scan_start = Time.now
      Shares.each do |share|
        register_and_scan share
      end
      last_scan_time = Time.now - last_scan_start
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
    Log.debug "Some change has happened with #{path}"
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

    Log.debug "Learning about #{relpath}"
    share.check_path path

    begin
      stat = File.stat path
    rescue Errno::ENOENT
      # File was deleted!
      if share[relpath]
        share[relpath].deleted = true
        share.save relpath
      end
      # Don't need to do anything if it was never seen.
      return
    end

    # Monitor directories and unreadable files
    send_monitor :monitor, path

    if stat.directory?
      Dir.foreach( path ) do |filename|
        next if filename == '.' || filename == '..'
        process_path share, "#{path}/#{filename}", &block
      end
      return
    end

    # Don't want pipes, sockets, devices, directories.. etc
    # FIXME this will also skip symlinks
    return unless stat.file?

    unless stat.readable?
      Log.warn "File #{path} is not readable. It will be skipped..."
      return
    end

    file_touched = false # need to update utime if file is changed

    file = share[relpath] || Share::File.create(relpath)

    # If mtime or sizes are different need to regenerate hash
    if file.mtime != stat.mtime || file.size != stat.size
      file.sha256 = nil
      file.commit stat
      @hash_queue.push [share, file]
      file_touched = true
    # If only the mode has changed then just update the record.
    elsif file.mode != stat.mode.to_s(8)
      file.commit stat
      file_touched = true
    end

    file.utime = Time.new.to_f if file_touched
    share[relpath] = file


    block.call relpath if block
  end

  def self.register_and_scan share
    @scanning = true

    known_files = Set.new(share.map { |f| f.path })
    process_path share, share.path do |relpath|
      known_files.delete relpath
    end

    # What is left over are the deleted files.
    known_files.each do |path|
      process_path share, path
    end

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

    loop do
      share, file = gunlock { @hash_queue.shift }
      next if file.sha256
      digest = Digest::SHA256.new
      gunlock {
        File.open share.full_path(file.path), 'rb' do |f|
          while data = f.read(1024 * 512)
            digest << data

            Thread.stop if @scanning
          end
        end
      }
      file.sha256 = digest.hexdigest
      share.save file.path
    end
  end

  def self.send_monitor method, *args
    return unless @change_monitor
    @change_monitor.send method, *args
  end
end
