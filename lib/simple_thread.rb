# This program uses a simplified locking model called "brain-dead threads".
# Most code is ran while holding a global lock, and code that is known to be
# safe can release the lock.
#
# More specific locking can be added where it will yield a performance increase.
#
# Note that we aren't aggressive about unlocking every single local I/O request
# in clearskies because it's a background daemon and we don't want it to
# consume too many resources.  If an I/O device is taking a long time to
# respond then we want to scale ourselves back appropriately.

require 'thread'
require_relative 'log'

# A thread should never abort since we're handling it in safe thread
Thread.abort_on_exception = true

$global_lock = Mutex.new
$global_lock_holder = nil
$global_lock_count = 0

module Kernel
  def lock_global_lock
    $global_lock.lock
    $global_lock_holder = Thread.current
    $global_lock_count += 1
  end

  def unlock_global_lock
    $global_lock_holder = nil
    $global_lock_count += 1
    $global_lock.unlock
  end

  def glock
    lock_global_lock
    begin
      return yield
    ensure
      unlock_global_lock
    end
  end

  def gunlock
    unlock_global_lock
    begin
      return yield
    ensure
      lock_global_lock
    end
  end

  def gsleep duration
    gunlock {
      sleep duration
    }
  end
end

class Thread
  attr_accessor :title
end

Thread.current.title = 'main'

class SimpleThread < Thread
  def initialize title=nil
    @title = title
    super do
      glock {
        begin
          yield
        rescue
          Log.error "Thread crash: #$!"
          $!.backtrace.each do |line|
            Log.error line
          end
        end
      }
    end
  end
end

# Spawn diagnostic thread.  It will detect if a blocking operation happens
# while holding the global lock.
#
# This won't detect blocking operations that take less than half a second
main_thread = Thread.current
SimpleThread.new('block_detector') do
  unlock_global_lock
  main_thread.run

  TIMES = 10

  loop do
    sleep 5

    lock_holder = $global_lock_holder
    lock_count = $global_lock_count
    next unless lock_holder

    TIMES.times do |i|
      sleep 0.050
      break if $global_lock_holder != lock_holder
      break if $global_lock_count != lock_count

      if i == TIMES - 1
        begin
          Log.warn "Blocking operation:"
          $global_lock_holder.backtrace.each do |line|
            Log.warn "    #{line}"
          end
        rescue
        end
      end
    end
  end
end

# Wait for diagnostic job to start running
Thread.stop
lock_global_lock
