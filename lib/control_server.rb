# Listen for controlling commands from user interfaces.
#
# See protocol/control.md for protocol documentation.

require 'json'
require 'safe_thread'
require 'access_code'
require 'pending_codes'

module ControlServer
  def self.start
    SafeThread.new do
      run
    end
  end

  private
  def self.run
    path = Conf.control_path
    if File.exists? path
      begin
        UNIXSocket.new path
        raise "Daemon already running"
      rescue Errno::ECONNREFUSED
        Log.info "Cleaning up old socket at #{path}"
        File.unlink path
      end
    end

    at_exit do
      File.unlink path rescue nil
    end

    server = UNIXServer.new path

    Log.info "Listening on #{server.path}"
    loop do
      client = gunlock { server.accept }
      SafeThread.new do
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
      time_to_exit = false
      break unless json
      command = JSON.parse json, symbolize_names: true
      begin
        res = handle_command command
      rescue SystemExit
        time_to_exit = true
        res = nil
      rescue
        Log.error "Control error: #$!"
        Log.error $!.backtrace.join( "\n" )
        res = { error: $!.class, message: $!.to_s }
      end
      res ||= {}
      client.puts res.to_json
      break if time_to_exit
    end
  end

  def self.handle_command command
    case command[:type].to_sym
    when :stop
      Log.debug "Control command to stop daemon, exiting"
      raise SystemExit
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
      end

      code = AccessCode.create
      share.add_code code
      Network.force_find_peer

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
      Network.force_find_peer

      nil

    else
      raise "Invalid control command: #{command[type].inspect}"
    end
  end
end
