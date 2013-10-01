# Scans for files.  If operating system support for monitoring files is
# available, use it to check for future changes, otherwise scan occasionally.

require 'thread'
require 'digest/sha2'
require 'find'

module Scanner
  def self.start
    @worker = Thread.new { work }
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

    last_scan_start = Time.new

    Shares.each do |share|
      register_and_scan share, change_monitor
    end

    Shares.each do |share|
      calculate_hashes share
    end

    last_scan_end

    if change_monitor
      loop do
        Thread.self.pause
      end
    end

    loop do
      sleep [last_scan_time * DELAY_MULTIPLIER, MIN_RESCAN].max
      Shares.each do |share|
        register_and_scan share, nil
      end
    end
  end

  # Return appropriate ChangeMonitor for platform
  def get_change_monitor
    nil
  end

  def register_and_scan share, change_monitor
    Find.find( share.path ) do |path|
      # Avoid race conditions by monitoring before scanning the file
      if change_monitor
        change_monitor.monitor path
      end

      next if File.directory? path

      # Make note of file metadata now.  We will come back and calculate
      # the SHA256 later.
    end
  end
end
