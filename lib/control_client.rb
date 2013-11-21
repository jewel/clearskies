# Communicate with the clearskies daemon over a local socket
#
# See protocol/control.md for documentation.

require 'socket'
require 'json'
require_relative 'conf'

module ControlClient
  # Serialize a command to JSON, send it to the daemon, and then parse and
  # return the result.
  def self.issue type, opts={}
    connect if !@socket
    opts[:type] = type
    json = opts.to_json

    json.gsub! "\n", ''

    @socket.puts json

    json = @socket.gets

    res = JSON.parse json, symbolize_names: true
    if res[:error]
      raise "server can't #{type.inspect}, says: #{res[:error]} #{res[:message]}"
    end

    res
  end

  private
  # Connect to the daemon over a unix domain socket, and do the handshake
  def self.connect
    begin
      @socket = UNIXSocket.open Conf.control_path
    rescue Errno::ENOENT
      abort "Daemon not running"
    end

    greeting = JSON.parse @socket.gets, symbolize_names: true

    unless greeting[:service] == 'ClearSkies Control'
      abort "Invalid daemon service: #{greeting.inspect}"
    end

    unless greeting[:protocol] == 1
      abort "Incompatible daemon protocol version: #{greeting[:protocol].inspect}"
    end
  end
end
