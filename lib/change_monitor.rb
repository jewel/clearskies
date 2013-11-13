# Module containing different file change monitors

module ChangeMonitor
  # Search for the best available method of monitoring changes
  def self.find
    begin
      require 'rb-inotify'
    rescue LoadError
      return nil
    end

    require_relative 'change_monitor/gem_inotify'
    return ChangeMonitor::GemInotify.new
  end
end
