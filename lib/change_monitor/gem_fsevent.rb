require 'set'
require 'rb-fsevent'
require_relative '../simple_thread'

module ChangeMonitor

  class GemFSEvent
    def initialize
      @notifier = FSEvent.new

      @on_change = nil

      @watching = []
    end

    def on_change &block
      @on_change = block
    end
    
    def register share
      path = share.path
      return if @watching.include? path
      @watching << path
      
      @notifier.stop
      
      @notifier.watch @watching do |dirs|
        dirs.map do |dir|
          glock do
            Log.info "changed: #{dir}"
            @on_change.call dir
          end
        end
      end

      Log.info "monitoring #{@watching}"
      
      SimpleThread.new 'fsevent' do
        gunlock {
          @notifier.run
        }
      end
    end
      
    def monitor path
    end
  end
  
end
