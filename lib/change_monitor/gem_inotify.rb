require 'rb-inotify'
require 'thread'

module ChangeMonitor

  class GemInotify
    ACTIONS = %w{create delete moved_to moved_from close_write modify}

    def initialize
      @notifier = INotify::Notifier.new

      @on_change = nil

      @watching = {}

      Thread.new do
        @notifier.run
      end
    end

    def on_change &block
      @on_change = block
    end

    def monitor path
      raise "Must specify callback with on_change" unless @on_change

      dir = File.dirname path

      return if @watching[dir]

      @notifier.watch(dir, *ACTIONS) do |event|
        p event
        @on_change.call event.watcher.path + '/' + event.name
      end

      @watching[dir]
    end
  end
end
