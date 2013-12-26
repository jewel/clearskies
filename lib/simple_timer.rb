# Timer actions that can be canceled
#
# This is a module to allow a single thread to run all timers for the entire
# program.
#
# Note that these timers are purposely imprecise, trading accuracy for
# efficiency.

require_relative 'simple_thread'
require_relative 'simple_condition'

module SimpleTimer
  def self.run_at time, &block
    init

    event = {
      time: time,
      block: block,
      canceled: false
    }

    @events << event

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

    @events = []

    @thread = SimpleThread.new 'timer' do
      loop do
        do_next_event
      end
    end

    @initialized = true
  end

  def self.do_next_event
    gsleep 0.2
    now = Time.new
    @events.delete_if do |event|
      next true if event[:canceled]
      next false unless event[:time] < now
      event[:block].call
      true
    end
  end
end
