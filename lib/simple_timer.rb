# Timer actions that can be canceled
#
# This is a module to allow a single thread to run all timers for the entire
# program.

require_relative 'simple_thread'
require_relative 'simple_condition'

module SimpleTimer
  def self.run_at time, &block
    warn "Running for #{time.to_f}"
    init

    id = @next_id
    @next_id += 1

    event = {
      time: time,
      id: id,
      block: block,
      canceled: false
    }

    if @current_event && time < @current_event[:time]
      # We unfortunately have already ran our main thread, so instead of trying
      # to interrupt it, we'll just start another thread for this event
      SimpleThread.new do
        wait_for_event event
      end
      return event
    end

    @events << event

    # FIXME This isn't an efficient approach if there are lots of events
    @events.sort_by { |_| _[:time] }

    @thread.wakeup

    event
  end

  def self.cancel event
    event[:canceled] = true
    @events.delete event
    nil
  end

  private
  def self.init
    return if @initialized

    @next_id = 1
    @events = []

    @current_event = nil

    @thread = SimpleThread.new 'timer' do
      loop do
        do_next_event
      end
    end

    @initialized = true
  end

  def self.do_next_event
    if @events.empty?
      gunlock {
        Thread.stop
      }
      return
    end

    @current_event = @events.shift
    wait_for_event @current_event
    @current_event = nil
  end

  def self.wait_for_event event
    time_to_sleep = event[:time] - Time.new
    gsleep time_to_sleep if time_to_sleep > 0
    return if event[:canceled]
    event[:block].call
  end
end
