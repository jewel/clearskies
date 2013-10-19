# Scans for files.  If operating system support for monitoring files is
# available, use it to check for future changes, otherwise scan occasionally.

require 'thread'
require 'digest/sha2'
require 'find'
require 'securerandom'
require 'pathname'

module Scanner
  DELAY_MULTIPLIER = 10
  MIN_RESCAN = 60
  def self.start
    @worker = Thread.new { work }
    @worker.abort_on_exception = true
  end

  def self.pause
    @worker.pause
  end

  def self.unpause
    @worker.start
  end

  # Thread entry point
  private
  def self.work
    sleep 2 # FIXME temporary for testing
    # TODO Lower own priority

    change_monitor = get_change_monitor

    change_monitor.on_change = monitor_callback if change_monitor

    last_scan_start = Time.now

    Shares.each do |share|
      register_and_scan share, change_monitor
    end

    Shares.each do |share|
      calculate_hashes share
    end

    last_scan_time = Time.now - last_scan_start

    if change_monitor
      loop do
        Thread.self.pause
      end
    end

    loop do
      next_scan_time = Time.now + [last_scan_time * DELAY_MULTIPLIER, MIN_RESCAN].max
      while Time.now < next_scan_time
        sleep next_scan_time - Time.now
        Shares.each do |share|
          calculate_hashes share
        end
      end

      last_scan_start = Time.now
      Shares.each do |share|
        register_and_scan share, nil
      end
      last_scan_time = Time.now - last_scan_start
    end
  end

  # Return appropriate ChangeMonitor for platform
  def self.get_change_monitor
    nil
  end

  def self.monitor_callback path
    #TODO: grab the global lock

    # Stat the file to check mtime and size

    # Add the file to the sha1 queue
  end

  def self.register_and_scan share, change_monitor
    Find.find( share.path ) do |path|
      stat = File.stat(path)
      relpath = share.partial_path path

      #don't want pipes, sockets, devices, directories.. etc
      # FIXME this will also skip symlinks
      next unless stat.file?

      unless stat.readable?
        warn 'File #{path} is not readable. It will be skipped...'
      end

      # Monitor it before we do anything
      if change_monitor
        change_monitor.monitor path
      end

      unless share[relpath]
        #This is the first time the file has ever been seen
        # Make note of file metadata now.  We will come back and calculate
        # the SHA256 later.
        file = Share::File.new
        file.path = relpath
        file.mode = stat.mode.to_s(8).to_i
        file.mtime = stat.mtime.to_i
        file.size = stat.size
        file.utime = Time.new.to_i
        file.id = SecureRandom.hex 16
        file.key = SecureRandom.hex 32

        share[relpath] = file
      end
    end
  end

  def self.calculate_hashes share
    share.each do |file|
      unless file.sha256
        file.sha256 = Digest::SHA256.file(share.full_path(file.path)).hexdigest
        share.save file.path
      end
    end
  end
end
