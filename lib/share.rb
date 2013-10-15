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
    path = "#{Conf.data_dir}/share_#{share_id}.db"
    @db = Permahash.new path

    @by_sha = {}
    self.each { |path,file| @by_sha[file.sha256] = file }

    @peer_id = @db[:peer_id] ||= SecureRandom.hex(32)
    @db.flush
  end

  def self.create path
    share = Share.new 'FIXME'
    share.path = path
    share
  end

  def path= path
    @db[:path] = path
  end

  def path
    @db[:path]
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
    @db["file/#{path}"] = file
  end

  # Make changes to the file objects atomic by needing to call save() after any
  # changes are made
  def save path
    @db["file/#{path}"] = @db["file/#{path}"]
  end
end
