# Debounce events, or remove similar events that happen in close succession.
#
# This adds a delay to all the events in order to reduce duplicates.
#
# Only the latest event will be emitted, as long as the events are less than
# "threshold" seconds together.

require_relative 'simple_thread'

class Debouncer
  DEFAULT_THREASHOLD = 0.2
  def initialize name, threshold=nil
    @threshold = threshold || DEFAULT_THREASHOLD
    @queue = Queue.new
    @latest = Hash.new
    @halt = false
    @worker = SimpleThread.new name do
      drain_queue
    end
  end

  def call category=nil, &block
    run_at = Time.new + @threshold
    @queue << [category, run_at, block]
    @latest[category] = run_at
  end

  def shutdown
    @halt = true
  end

  private
  def drain_queue
    loop do
      break if @halt

      category, run_at, block = gunlock { @queue.pop }

      now = Time.new
      if run_at > now
        gsleep run_at - now
      end

      # Check and see if another event has come in like this one while it was
      # sitting in the queue or waiting to run
      if @latest[category] > run_at
        next
      end

      @latest.delete category
      block.call
    end
  end
end
