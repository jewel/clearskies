# Hold configuration information about the running instance
#
# TODO This will eventually be parsed from a config file and overridden with
# environment variables or command-line options

require 'fileutils'

module Conf
  def self.data_dir filename=nil
    # FIXME Is this the proper default directory?
    path = ENV['CLEARSKIES_DIR'] || "#{ENV['HOME']}/.local/share/clearskies"
    FileUtils.mkdir_p path
    path = "#{path}/#{filename}" if filename
    path
  end

  def self.listen_port
    0
  end

  def self.control_path
    data_dir "control"
  end

  def self.version
    "clearskies 0.1pre"
  end
end
