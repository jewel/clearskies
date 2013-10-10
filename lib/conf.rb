# Hold configuration information about the running instance
#
# TODO This will eventually be parsed from a config file and overridden with
# environment variables or command-line options

require 'fileutils'

module Conf
  def self.data_dir
    # FIXME Is this the right place according to the relevant standard?
    path = "#{ENV['HOME']}/.local/share/clearskies"
    FileUtils.mkdir_p path
    path
  end

  def self.listen_port
    0
  end

  def self.control_listen_port
    60106
  end
end
