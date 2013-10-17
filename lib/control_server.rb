# Listen for controlling commands from user interfaces.
#
# See protocol/control.md for protocol documentation.

require 'json'
require 'thread'
require 'access_code'
require 'pending_codes'

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
        warn "Control error: #$!"
        warn $!.backtrace.join( "\n" )
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
      Thread.new do
        sleep 0.2
        exit
      end
      nil

    when :pause
      Network.pause
      nil

    when :resume
      Network.resume
      nil

    when :status
      {
        paused: false,
        tracking: false,
        nat_punctured: false,
        upload_rate: 0,
        download_rate: 0,
      }

    when :create_share
      share = Share.create command[:path]
      Shares.add share
      nil

    when :create_access_code
      share = Shares.by_path command[:path]
      if !share
        share = Share.create command[:path]
        Shares.add share
        warn "Now we have a share, #{share.inspect} inside of #{Shares.inspect}"
      end

      code = AccessCode.create
      share.add_code code

      {
        access_code: code.to_s
      }

    when :list_shares
      {
        shares: Shares.map do |share|
          {
            path: share.path,
            status: share.status,
          }
        end
      }

    when :add_share
      FileUtils.mkdir_p command[:path]
      code = PendingCode.parse(command[:code])
      code.path = command[:path]
      PendingCodes.add code
      nil

    else
      raise "Invalid control command: #{command[type].inspect}"
    end
  end
end
