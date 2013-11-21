# Hold configuration information about the running instance
#
# TODO This will eventually be parsed from a config file and overridden with
# environment variables or command-line options

require 'fileutils'

module Conf
  # Where should we store information about shares and peers?
  def self.data_dir filename=nil
    # FIXME Is this the proper default directory?
    path = ENV['CLEARSKIES_DIR'] || "#{ENV['HOME']}/.local/share/clearskies"
    FileUtils.mkdir_p path
    path = "#{path}/#{filename}" if filename
    path
  end

  # Get the path to a file in the "data_dir" directory
  def self.path filename
    data_dir filename
  end

  # Port to listen on for incoming clearskies connections.  A port of "0" means
  # to pick a random port each time the daemon starts.
  def self.listen_port
    0
  end

  # Path to unix socket used by CLI to control the daemon
  def self.control_path
    data_dir "control"
  end

  # Version of this software
  def self.version
    "clearskies 0.1pre"
  end

  # A friendly name for this computer.  This is sent to peers.
  def self.friendly_name
    "ClearSkies Client"
  end
end
