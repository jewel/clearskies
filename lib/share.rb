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
require 'peer'

class Share
  include Enumerable
  attr_reader :id

  def initialize share_id
    @id = share_id

    path = "#{Conf.data_dir}/share_#{share_id}.db"
    @db = Permahash.new path

    @by_sha = {}
    self.each { |file| @by_sha[file.sha256] = file }

    @db[:codes] ||= []
    @db[:peers] ||= []
    @db[:version] ||= Time.new.to_f

    @db.flush

    @subscribers = []
  end

  def check_key_type_and_level type, level
    raise "Invalid key type #{type.inspect}" unless [:rsa, :psk].include? type
    raise "Invalid access level" unless [:read_write, :read_only, :untrusted].include? level
  end

  def version
    @db[:version]
  end

  def peer_id= val
    @db[:peer_id] = val
  end

  def peer_id
    @db[:peer_id]
  end

  def set_key type, level, key
    check_key_type_and_level type, level

    @db[type] ||= {}
    @db[type][level] = key

    # Force a save
    @db[type] = @db[type]
  end

  def key type, level
    check_key_type_and_level type, level

    @db[type][level]
  end

  def self.create path
    psks = {
      :read_write => SecureRandom.hex(16),
      :read_only  => SecureRandom.hex(16),
      :untrusted  => SecureRandom.hex(16),
    }

    # FIXME Temporarily at 512 until it can be done in the background, since
    # 4096 drains the available entropy and takes too long for testing
    pkeys = {
      :read_write => OpenSSL::PKey::RSA.new(512).to_s,
      :read_only  => OpenSSL::PKey::RSA.new(512).to_s,
    }

    share_id = Digest::SHA256.hexdigest psks[:read_write]
    share = Share.new share_id
    share.path = path
    share.peer_id = SecureRandom.hex 16

    psks.each  { |k,v| share.set_key :psk, k, v }
    pkeys.each { |k,v| share.set_key :rsa, k, v }

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
      next if val.deleted
      yield val
    end
  end

  def add_code code
    @db[:codes] << code

    # force save
    @db.save :codes
  end

  def each_code
    @db[:codes].each do |code|
      yield code
    end
  end

  def add_peer peer
    @db[:peers] << peer

    # force save
    @db.save :peers
  end

  def each_peer
    @db[:peers].each do |peer|
      yield peer
    end
  end

  def [] path
    @db["file/#{path}"]
  end

  def []= path, file
    @db["file/#{path}"] = file
    @db[:version] = Time.new.to_f
    notify file
    file
  end

  def full_path partial_path
    "#{path}/#{partial_path}"
  end

  # Return a relative path to a file in the share from a full path
  def partial_path full_path
    Pathname.new(full_path).relative_path_from(Pathname.new(path)).to_s
  end

  # Make changes to the file objects atomic by needing to call save() after any
  # changes are made
  def save path
    @db.save "file/#{path}"
    @db[:version] = Time.new.to_f
    notify @db["file/#{path}"]
  end

  def subscribe &block
    @subscribers << block
  end

  private
  def notify file
    raise "Nil file" unless file
    @subscribers.each do |block|
      block.call file
    end
  end
end
