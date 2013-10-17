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
    @db[:codes] ||= []

    @db.flush
  end

  def self.create path
    share_id = SecureRandom.hex 16
    share = Share.new share_id
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
    # FIXME
    "abcdef"
  end

  def access_level
    :read_write
  end

  def access_level= val
    # FIXME
  end

  def each
    @db.each do |key,val|
      next unless key =~ /\Afile\//
      yield key, val
    end
  end

  def add_code code
    @db[:codes] << code

    # force save
    @db[:codes] = @db[:codes]
  end

  def each_code
    @db[:codes].each do |code|
      yield code
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
