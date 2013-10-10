# Represents a single share, and all its files
#
# Data about all the files in the share are stored in a single
# permahash.
require 'share/file'
require 'permahash'
require 'securerandom'
require 'conf'

class Share
  attr_reader :id, :peer_id

  def initialize share_id
    @id = share_id
    path = "#{Conf.data_path}/share_#{share_id}.db"
    @db = Permahash.new path

    @by_sha = {}
    self.each { |path,file| @by_sha[file.sha256] = file }

    @peer_id = @db[:peer_id] ||= SecureRandom.hex(32)
  end

  def key level
    nil
  end

  def each
    @db.each do |key,val|
      next unless key =~ /\Afile\//
      yield key, val
    end
  end

  def [] path
    @db["file/#{path}"]
  end

  def []= path, file
    file.on_save do
      @db["file/#{path}"] = file
    end
    file.save!
  end
end
