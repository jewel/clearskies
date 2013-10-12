# Listen for controlling commands from user interfaces.
#
# See protocol/control.md for protocol documentation.

require 'json'
require 'thread'

module ControlServer
  def self.run
    path = Conf.control_path
    if File.exists? path
      begin
        UNIXSocket.new path
        raise "Daemon already running"
      rescue Errno::ECONNREFUSED
        warn "Cleaning up old socket at #{path}"
        File.unlink path
      end
    end

    at_exit do
      File.unlink path rescue nil
    end

    server = UNIXServer.new path

    warn "Listening on #{server.path}"
    loop do
      client = server.accept
      Thread.new do
        serve client
      end
    end
  end

  private
  def self.serve client
    client.puts({
      service: 'ClearSkies Control',
      software: Conf.version,
      protocol: 1,
    }.to_json)

    loop do
      json = client.gets
      break unless json
      command = JSON.parse json, symbolize_names: true
      begin
        res = handle_command command
      rescue
        res = { error: $!.class, message: $!.to_s }
      end
      res ||= {}
      client.puts res.to_json
    end
  end

  def self.handle_command command
    case command[:type].to_sym
    when :stop
      warn "Control command to stop daemon, exiting"
      exit
    when :pause
    when :resume
    when :status
      {
        paused: false,
        tracking: false,
        nat_punctured: false,
        upload_rate: 0,
        download_rate: 0,
      }
    when :create_share
    when :list_shares
    end
  end
end
