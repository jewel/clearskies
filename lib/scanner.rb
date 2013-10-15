# Scans for files.  If operating system support for monitoring files is
# available, use it to check for future changes, otherwise scan occasionally.

require 'thread'
require 'digest/sha2'
require 'find'

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
      # Avoid race conditions by monitoring before scanning the file
      if change_monitor
        change_monitor.monitor path
      end

      next if File.directory? path

      # Make note of file metadata now.  We will come back and calculate
      # the SHA256 later.
      unless share[path]
        share[path] = Share::File.new(:path => path)
      end
    end
  end

  def self.calculate_hashes share
    share.each do |file|
      unless file.sha256 
        file.sha256 = Digest::SHA256.file(share.path).hexdigest
      end
    end
  end
end
