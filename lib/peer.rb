# Track what we know about a peer
#
# This information is made permanent as part of the corresponding Share

class Peer
  attr_accessor :id, :friendly_name, :manifest, :updates

  def initialize
    @updates = []
  end
end
