# Module containing different file change monitors

module ChangeMonitor
  # Search for the best available method of monitoring changes
  def self.find
    begin
      require 'rb-inotify'
    rescue LoadError
      Log.warning "Cannot load a file change monitor, is rb-inotify installed?"
      return nil
    end

    require_relative 'change_monitor/gem_inotify'
    Log.info "Using rb-inotify to watch for file changes"
    return ChangeMonitor::GemInotify.new
  end
end
