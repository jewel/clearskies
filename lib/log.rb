# Write to log file and to screen.

module Log
  LEVELS = [:debug, :info, :warn, :error, :none]

  # Give an open file object to send logs
  def self.file_handle= fp
    @file_handle = fp
  end

  # Set the maximum level that will be sent to the screen
  def self.screen_level= level
    @screen_level = level
  end

  # Set the maximum level that will be sent to the file
  def self.file_level= level
    @file_level = level
  end

  # Inspect the objects and write the resulting strings to the debug log
  def self.p *objs
    objs.each do |obj|
      log :debug, obj.inspect
    end
  end

  # Write a message to the log at "debug" level.
  def self.debug msg
    log :debug, msg
  end

  # Write a message to the log at "info" level.
  def self.info msg
    log :info, msg
  end

  # Write a message to the log at "warn" level.
  def self.warn msg
    log :warn, msg
  end

  # Write a message to the log at "error" level.
  def self.error msg
    log :error, msg
  end

  # Write a message to the log, with given level.
  def self.log level, msg
    @screen_level ||= :warn
    if Thread.current.respond_to?(:title) && Thread.current.title
      msg = "#{Thread.current.title}> #{msg}"
    end

    if intval(level) >= intval(@screen_level)
      # ANSI color code when possible
      if STDERR.tty?
        case level
        when :error
          msg = "\e[31m\e[1m" + msg + "\e[0m"
        when :warn
          msg = "\e[33m" + msg + "\e[0m"
        when :info
          msg = "\e[34m" + msg + "\e[0m"
        end
      end
      Kernel.warn msg
    end

    @file_level ||= :debug
    if @file_handle && intval(level) >= intval(@file_level)
      timestamp = Time.now.strftime "%H:%M:%S.%N"
      @file_handle.write "#{timestamp} #{level} #{msg}\n"
    end
  end

  private
  # Get integer value representing the level, for sorting
  def self.intval level
    LEVELS.index level
  end
end
