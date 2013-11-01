require 'safe_thread'
require 'log'
require 'conf'

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
    begin
      Process.setpriority( Process::PRIO_USER, 0, 15 )
    rescue Errno::EACCES
      # FIXME Log.file_handle isn't set yet
      Log.debug "Permission denied when trying to setpriority"
    end

    run
  end

  def self.run
    Log.screen_level = :debug
    Log.file_handle = File.open Conf.path( 'log' ), 'a'

    File.open Conf.path("pid"), 'w' do |f|
      f.puts $$
    end

    require 'shares'
    require 'share'

    require 'scanner'
    Scanner.start

    require 'network'
    Network.start

    require 'control_server'
    ControlServer.start

    gunlock { Thread.stop }
  end
end
