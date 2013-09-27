module Daemon
  def self.start
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

    require 'database'
    Database.start

    require 'scanner'
    Scanner.start

    require 'network'
    Network.start

    require 'control'
    Control.start

    Control.wait
  end
end
