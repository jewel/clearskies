# This program uses a simplified locking model called "brain-dead threads".
# Most code is ran while holding a global lock, and code that is known to be
# safe to run in parallel releases the lock.
#
# More specific locking can be added where it will yield a performance increase.

require 'thread'

# A thread should never abort since we're handling it in safe thread
Thread.abort_on_exception = true

$global_lock = Mutex.new

class SafeThread < Thread
  def initialize
    super do
      $global_lock.lock
      $global_lock_holder = Thread.current
      begin
        yield
      rescue
        warn "Thread crash: #$!"
        $!.backtrace.each do |line|
          warn line
        end
      end
    end
  end
end

# Spawn diagnostic thread.  It will detect if a blocking operation happens
# while holding the global lock.
#
# This won't detect blocking operations that take less than half a second
main_thread = Thread.current
SafeThread.new do
  $global_lock_holder = nil
  $global_lock.unlock
  main_thread.run

  loop do
    sleep 5

    $lock_holder = $global_lock_holder
    next unless $lock_holder

    10.times do |i|
      sleep 0.050
      break if $global_lock_holder != $lock_holder

      if i == 9
        begin
          warn "Blocking operation:"
          $global_lock_holder.backtrace.each do |line|
            warn "    #{line}"
          end
        rescue
        end
      end
    end
  end
end

# Wait for diagnostic job to start running
Thread.stop
$global_lock.lock
$global_lock_holder = Thread.current

module Kernel
  def glock
    $global_lock.lock
    $global_lock_holder = Thread.current
    begin
      return yield
    ensure
      $global_lock_holder = nil
      $global_lock.unlock
    end
  end

  def gunlock
    $global_lock_holder = nil
    $global_lock.unlock
    begin
      return yield
    ensure
      $global_lock.lock
      $global_lock_holder = Thread.current
    end
  end

  def gsleep duration
    gunlock {
      sleep duration
    }
  end
end
