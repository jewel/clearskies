# Represents a single share, and all its files
#
# Data about all the files in the share are stored in a single
# permahash.
require 'share/file'
require 'permahash'
require 'securerandom'
require 'conf'
require 'openssl'
require 'digest'

class Share
  attr_reader :id, :peer_id

  def initialize share_id
    path = "#{Conf.data_dir}/share_#{share_id}.db"
    @db = Permahash.new path

    @by_sha = {}
    self.each { |path,file| @by_sha[file.sha256] = file }

    # Peer_id is always unique, so it can be created here.  Unlike the psks and 
    # the pkeys.
    @db[:peer_id] ||= SecureRandom.hex(16)
    @db[:codes]   ||= []

    @db.flush
  end

  # Make sure values in @db look sane. Helpful when loading from disk
  # or creating over the network.
  def validate_share
    #TODO
  end

  def check_key_type_and_level type,level
    raise "Invalid key type #{type}." unless [:pkey, :psk].include? type
    raise "Invalid access level" unless [:read_write, :read_only, :untrusted].include? level
  end

  def set_key type, level, key
    check_key_type_and_level type,level

    @db[type] ||= {} 
    @db[type][level] = key

    #force a save
    @db[type] = @db[type]
  end

  def key type, level
    check_key_type_and_level type,level

    @db[type][level]
  end

  def self.create path
    psks = {
      :read_write => SecureRandom.hex(16),
      :read_only  => SecureRandom.hex(16),
      :untrusted  => SecureRandom.hex(16),
    }
    pkeys = {
      :read_write => OpenSSL::PKey::RSA.new(4096).to_s,
      :read_only  => OpenSSL::PKey::RSA.new(4096).to_s,
    }
    share_id = Digest::SHA256.hexdigest(psks[:read_write])
    share = Share.new share_id
    share.path = path
    psks.each  { |k,v| share.set_key  :psk, k, v }
    pkeys.each { |k,v| share.set_key :pkey, k, v }
    share
  end

  def path= path
    @db[:path] = path
  end

  def path
    @db[:path]
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
