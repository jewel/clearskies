# Write to log file and to screen, as appropriate

require 'conf'

module Log
  LEVELS = [:debug, :info, :warn, :error, :none]
  def self.screen_level= level
    @screen_level = level
  end

  def self.file_level= level
    @file_level = level
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
    @screen_level ||= :debug
    if intval(level) >= intval(@screen_level)
      Kernel.warn msg
    end

    @file_level ||= :debug
    if intval(level) >= intval(@file_level)
      @file ||= File.open Conf.path('log'), 'wb'
      timestamp = Time.now.strftime "%H:%M:%S.%N"
      @file.write "#{timestamp} #{msg}\n"
    end
  end

  private
  def self.intval level
    LEVELS.index level
  end
end
