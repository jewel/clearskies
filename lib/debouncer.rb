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
    @events = {}
    @oldest = nil
    @halt = false
    SimpleThread.new name do
      drain_queue
    end
  end

  def call category=nil, &block
    time = Time.new
    @oldest = time + @threshold unless @oldest
    @events[category] = [block, time + @threshold]
  end

  def shutdown
    @halt = true
  end

  private
  def drain_queue
    loop do
      break if @halt

      if !@oldest
        gsleep @threshold
        next
      end

      now = Time.new
      if @oldest > now
        gsleep @oldest - now
      end

      oldest = nil

      @events.each do |category,info|
        block, run_at = info
        if run_at > Time.new
          oldest = run_at if !oldest || run_at < oldest
          next
        end
        @events.delete category
        block.call
      end

      @oldest = oldest
    end
  end
end
