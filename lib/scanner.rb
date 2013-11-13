# Scans for files.  If operating system support for monitoring files is
# available, use it to check for future changes, otherwise scan occasionally.

require 'digest/sha2'
require 'set'
require 'find'
require 'securerandom'
require 'pathname'
require_relative 'change_monitor'
require_relative 'hasher'
require_relative 'log'

module Scanner
  DELAY_MULTIPLIER = 10
  MIN_RESCAN = 60 # an absolute minimum
  def self.start
    load_change_monitor

    Hasher.start
    @scanning = false

    @worker = SimpleThread.new 'scanner' do
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

    Log.debug "Performing first scan of all shares"
    last_scan_start = Time.now

    Shares.each do |share|
      register_and_scan share
    end

    last_scan_time = Time.now - last_scan_start
    Log.debug "Finished first scan of all shares"

    rescan_min = MIN_RESCAN
    rescan_min = 60*60 if @change_monitor # only once an hour

    loop do
      next_scan_time = Time.now + [last_scan_time * DELAY_MULTIPLIER, rescan_min].max
      Log.debug "Next scan of shares in #{(next_scan_time - Time.now).round} seconds"
      while Time.now < next_scan_time
        gsleep [next_scan_time - Time.now,0].max
      end

      Log.debug "Performing recurring scan of all shares"
      last_scan_start = Time.now
      Shares.each do |share|
        register_and_scan share
      end
      last_scan_time = Time.now - last_scan_start
      Log.debug "Finished recurring scan of all shares"
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
      if file = share[relpath]
        Log.debug "#{relpath} was deleted"
        file.deleted = true
        file.utime = Time.new.to_f
        share.save relpath
        return
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
    stat_mtime = [stat.mtime.to_i, stat.mtime.nsec]
    if file.mtime != stat_mtime || file.size != stat.size
      if share[relpath]
        Log.debug "#{relpath} has changed"
      else
        Log.debug "#{relpath} is new"
      end
      file.sha256 = nil
      file.commit stat
      Hasher.push share, file
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
    Hasher.pause
    Log.info "Doing scan of share #{share.path}"

    known_files = Set.new(share.map { |f| f.path })
    process_path share, share.path do |relpath|
      known_files.delete relpath
    end

    # What is left over are the deleted files.
    known_files.each do |path|
      process_path share, share.full_path(path)
    end
    Log.info "Finished scan of share #{share.path}"

  ensure
    Hasher.resume
  end


  def self.send_monitor method, *args
    return unless @change_monitor
    @change_monitor.send method, *args
  end
end
