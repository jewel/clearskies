require 'thread'
Thread.abort_on_exception = true

module Daemon
  def self.daemonize
    pid = fork
    raise 'First fork failed' if pid == -1
    return if pid

    Process.setsid
    pid = fork
    raise 'Second fork failed' if pid == -1
    exit if pid

    Dir.chdir '/'
    File.umask 0000

    STDIN.reopen '/dev/null'
    STDOUT.reopen '/dev/null', 'a'
    STDERR.reopen STDOUT

    # Run as low priority
    Process.setpriority( Process::PRIO_USER, 0, 15 )

    run
  end

  def self.run
    require 'shares'
    require 'share'

    require 'scanner'
    Scanner.start

    require 'network'
    Network.start

    require 'control_server'
    ControlServer.run
  end
end
