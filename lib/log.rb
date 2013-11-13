# Write to log file and to screen.

module Log
  LEVELS = [:debug, :info, :warn, :error, :none]

  def self.file_handle= fp
    @file_handle = fp
  end

  def self.screen_level= level
    @screen_level = level
  end

  def self.file_level= level
    @file_level = level
  end

  def self.p *objs
    objs.each do |obj|
      log :debug, obj.inspect
    end
  end

  def self.debug msg
    log :debug, msg
  end

  def self.info msg
    log :info, msg
  end

  def self.warn msg
    log :warn, msg
  end

  def self.error msg
    log :error, msg
  end

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
        when :warning
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
  def self.intval level
    LEVELS.index level
  end
end
