# Track what we know about a peer.
#
# This information is made permanent as part of the corresponding Share.

class Peer
  attr_accessor :id, :friendly_name, :manifest, :updates

  def initialize
    @updates = []
  end

  # Find the most-recent information known about a file.
  def find_file path
    # FIXME It'd be much more efficient to index this information in a hash,
    # which would also let us drop old information
    @updates.reverse.each do |update|
      return update[:file] if update[:file][:path] == path
    end

    @manifest[:files].each do |file|
      return file if file[:path] == path
    end

    return nil
  end
end
