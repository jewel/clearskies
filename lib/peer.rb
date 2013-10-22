# Track what we know about a peer
#
# This information is made permanent as part of the corresponding Share

class Peer
  attr_accessor :id, :friendly_name, :manifest, :updates

  def initialize
    @updates = []
  end

  def find_file path
    @updates.reverse.each do |update|
      return update[:file] if update[:file][:path] == path
    end

    @manifest[:files].each do |file|
      return file if file[:path] == path
    end

    return nil
  end
end
