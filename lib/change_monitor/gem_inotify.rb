require 'rb-inotify'
require 'safe_thread'

module ChangeMonitor

  class GemInotify
    ACTIONS = %w{attrib create delete moved_to moved_from close_write modify}

    def initialize
      @notifier = INotify::Notifier.new

      @on_change = nil

      @watching = {}

      SafeThread.new do
        gunlock {
          @notifier.run
        }
      end
    end

    def on_change &block
      @on_change = block
    end

    def monitor path
      raise "Must specify callback with on_change" unless @on_change

      path = File.dirname path unless File.directory? path

      return if @watching[path]

      @notifier.watch(path, *ACTIONS) do |event|
        glock do
          @on_change.call event.watcher.path + '/' + event.name
        end
      end

      @watching[path] = true
    end
  end
end
