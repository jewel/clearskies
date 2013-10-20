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
    load_change_monitor
  end

  def self.pause
    @worker.pause
  end

  def self.unpause
    @worker.start
  end

  def self.add_share share
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

    Shares.each do |share|
      calculate_hashes share
    end

    last_scan_time = Time.now - last_scan_start

    return if @change_monitor

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
  def self.load_change_monitor
    begin
      require 'rb-inotify'
    rescue LoadError
      return
    end

    require 'change_monitor/gem_inotify'
    @change_monitor = ChangeMonitor::GemInotify.new
    @change_monitor.on_change do |path|
      monitor_callback path
    end
  end

  def self.monitor_callback path
    warn "Some change has happened with #{path}"
    #TODO: grab the global lock

    # Stat the file to check mtime and size

    # Add the file to the sha256 queue
  end

  def self.register_and_scan share
    Find.find( share.path ) do |path|
      p path
      stat = File.stat(path)
      relpath = share.partial_path path

      # Monitor directories and unreadable files
      send_monitor :monitor, path

      # Don't want pipes, sockets, devices, directories.. etc
      # FIXME this will also skip symlinks
      next unless stat.file?

      unless stat.readable?
        warn 'File #{path} is not readable. It will be skipped...'
      end

      unless share[relpath]
        # This is the first time the file has ever been seen
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

  def self.send_monitor method, *args
    return unless @change_monitor
    @change_monitor.send method, *args
  end
end
