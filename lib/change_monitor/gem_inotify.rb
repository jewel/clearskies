require 'rb-inotify'
require_relative '../simple_thread'
require_relative '../debouncer'

module ChangeMonitor

  class GemInotify
    ACTIONS = %w{attrib create delete moved_to moved_from close_write modify}

    def initialize
      @notifier = INotify::Notifier.new

      @debouncer = Debouncer.new "debounce-inotify", 0.05

      @on_change = nil

      @watching = {}

      SimpleThread.new 'inotify' do
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

      # We only need to monitor paths
      path = File.dirname path unless File.directory? path

      return if @watching[path]

      @notifier.watch(path, *ACTIONS) do |event|
        glock do
          fullpath = event.watcher.path + '/' + event.name
          @debouncer.call(fullpath) do
            @on_change.call fullpath
          end
        end
      end

      @watching[path] = true
    end
  end
end
