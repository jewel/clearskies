# Daemon-control code.  This starts and stops the daemon.

require_relative 'simple_thread'
require_relative 'log'
require_relative 'conf'
require_relative 'shares'
require_relative 'share'
require_relative 'scanner'
require_relative 'network'
require_relative 'control_server'

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

    run
  end

  def self.run
    Log.screen_level = :debug
    Log.file_handle = File.open Conf.path( 'log' ), 'a'

    File.open Conf.path("pid"), 'w' do |f|
      f.puts $$
    end

    # Run as low priority
    begin
      Process.setpriority Process::PRIO_PROCESS, $$, 15
    rescue Errno::EACCES, Errno::EPERM
      Log.warn "Permission denied when trying to lower priority"
    end

    Scanner.start

    Network.start

    ControlServer.start

    gunlock { Thread.stop }
  end
end
