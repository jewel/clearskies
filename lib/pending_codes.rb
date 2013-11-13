# Keep track of incoming access codes (codes generated on
# other nodes for shares we do not yet have).

require 'fileutils'
require_relative 'permahash'
require_relative 'pending_code'

class PendingCodes
  path = Conf.data_dir "pending_codes.db"
  @db = Permahash.new path

  def self.add code
    @db[code] = true
  end

  def self.delete code
    @db.delete code
  end

  def self.each
    @db.each do |code,val|
      yield code
    end
  end
end
