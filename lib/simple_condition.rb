# A ConditionVariable that uses the global lock of SimpleThread

require_relative 'simple_thread'

class SimpleCondition
  def initialize
    @var = ConditionVariable.new
  end

  def wait timeout=nil
    $global_lock_holder = nil
    $global_lock_count += 1
    @var.wait $global_lock, timeout
    $global_lock_holder = Thread.current
    $global_lock_count += 1
  end

  def broadcast
    @var.broadcast
  end

  def signal
    @var.signal
  end
end
