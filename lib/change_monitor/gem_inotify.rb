require 'rubygems'
require 'rb-inotify'
require 'thread'

module ChangeMonitor

  class RbInotify
    def initialize
      @notifier = INotify::Notifier.new

      @on_change = nil

      Thread.new do
        @notifier.run
      end
    end

    def on_change &block
      @on_change = block
    end

    def monitor path
      throw "Must specify callback with on_change before calling monitor" unless @on_change
      if File.directory?(path)
        #TODO: modify might be unnecessary on directories
        @notifier.watch(path, :create, :delete,
                        :moved_to, :moved_from,
                       :close_write, :modify) do |event|
          @on_change.call event.watcher.path + '/' + event.name
        end
      elsif File.file?(path)
        @notifier.watch(path, :modify) do |event|
          @on_change.call event.watcher.path + '/' + event.name
        end
      else
        throw "Invalid path: #{path}"
      end
    end
  end
end
