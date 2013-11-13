# A pending code is a representation of an access code for a share we didn't
# create.

require_relative 'access_code'

class PendingCode < AccessCode
  attr_reader :peer_id
  attr_accessor :path

  def initialize payload
    super payload
    @peer_id = SecureRandom.hex 16
  end
end
