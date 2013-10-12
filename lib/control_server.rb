# Listen for controlling commands from user interfaces.
#
# See protocol/control.md for protocol documentation.

require 'json'

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
      Thread.new { serve client }
    end
  end

  private
  def self.serve client
    warn "Serving #{client}"
    client.sync = true

    client.puts({
      service: 'ClearSkies Control',
      software: Connection::SOFTWARE,
      protocol: 1,
    }.to_json)

    loop do
      json = client.gets
      break unless json
      command = JSON.parse json, symbolize_keys: true
      begin
        res = handle_command command
      rescue
        res = { error: $!.class, message: $!.to_s }
      end
      client.puts res.to_json
    end
  end

  def self.handle_command command
    case command[:type]
    when :stop
      exit
    when :pause
    when :resuce
    when :status
    when :create_share
    when :list_shares
    end
  end
end
