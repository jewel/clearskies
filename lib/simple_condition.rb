# A ConditionVariable that uses the global lock of SimpleThread

require_relative 'simple_thread'

class SimpleCondition
  def initialize
    @var = ConditionVariable.new
  end

  def wait timeout=nil
    @var.wait $global_lock, timeout
  end

  def broadcast
    @var.broadcast
  end

  def signal
    @var.signal
  end
end
