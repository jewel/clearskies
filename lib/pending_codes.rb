# Keep track of incoming access codes (codes generated on
# other nodes for shares we do not yet have)

require 'permahash'
require 'fileutils'

class PendingCodes
  path = Conf.data_dir "pending_codes.db"
  @db = Permahash.new path
  @db.sync = true

  def self.add path, code
    FileUtils.mkdir_p path
    @db[code] = path
  end

  def self.delete code
    @db.delete code
  end

  def self.each
    @db.each do |path,code|
      yield path, code
    end
  end
end
