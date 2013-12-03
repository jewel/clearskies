# Represents a single share, and all its files.
#
# Data about all the files in the share are stored in a single
# permahash.

require 'securerandom'
require 'openssl'
require 'digest/sha2'
require 'pathname'
require_relative 'share/file'
require_relative 'permahash'
require_relative 'conf'
require_relative 'peer'
require_relative 'access_code'

class Share
  include Enumerable
  attr_reader :id

  # Load a share's information from database, or create a new share if the
  # database doesn't exist.
  def initialize share_id
    @id = share_id

    path = "#{Conf.data_dir}/share_#{share_id}.db"
    @db = Permahash.new path

    @by_sha = {}
    self.each { |file| @by_sha[file.sha256] = file }

    @db[:codes] ||= []
    @db[:peers] ||= []
    @db[:version] ||= Time.new.to_f

    @subscribers = []
  end

  # Validate that the crypto key type and level asked for is valid
  def check_key_type_and_level type, level
    raise "Invalid key type #{type.inspect}" unless [:rsa, :psk].include? type
    raise "Invalid access level" unless [:read_write, :read_only, :untrusted].include? level
  end

  # Get the share's database version, as needed by the protocol.
  def version
    @db[:version]
  end

  # Set our own peer_id for this share
  def peer_id= val
    @db[:peer_id] = val
  end

  # Get our peer_id for this share
  def peer_id
    @db[:peer_id]
  end

  # Set crypto key.  See `check_key_type_and_level` for valid parameter values.
  def set_key type, level, key
    check_key_type_and_level type, level

    @db[type] ||= {}
    @db[type][level] = key

    # Force a save
    @db[type] = @db[type]
  end

  # Get a crypto key for the share
  def key type, level
    check_key_type_and_level type, level

    @db[type][level]
  end

  # Create a new share for `path`
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

  # Set the path of the share
  def path= path
    @db[:path] = path
  end

  # Get the path of the share
  def path
    @db[:path]
  end

  # Get our access level to this share
  def access_level
    :read_write
  end

  # Set our access level to this share
  def access_level= val
    # FIXME
  end

  # Loop through each file in the share
  def each
    @db.each do |key,val|
      next unless key =~ /\Afile\//
      yield val
    end
  end

  # Add an access code to the share
  def add_code code
    @db[:codes] << code

    # force save
    @db.save :codes
  end

  # Loop through each access code associated with the share.
  def each_code
    @db[:codes].each do |code|
      yield code
    end
  end

  # Remove access code
  def delete_code code
    @db[:codes].delete code
    @db.save :codes
  end

  # Add a peer to the share
  def add_peer peer
    @db[:peers] << peer

    # force save
    @db.save :peers
  end

  # Loop through each peer
  def each_peer
    @db[:peers].each do |peer|
      yield peer
    end
  end

  # Get information about a file.
  def [] path
    @db["file/#{path}"]
  end

  # Save information about a file.
  def []= path, file
    @db["file/#{path}"] = file
    @db[:version] = Time.new.to_f
    notify file
    file
  end

  # Validate that the given path is safe to write to or read from, and is part
  # of a path.  This stops a peer from trying to read system files or other
  # sensitive files outside of the share path.
  def check_path full
    partial = partial_path full
    if partial =~ /\A\.\./
      raise SecurityError.new( "Attempt to access #{full.inspect} from share #{self.path}" )
    end

    # Verify that we're not following any symlinks
    #
    # FIXME we should really support symlinks as long as they point inside of
    # our share
    partial_parts = partial.split '/'
    parts = []
    partial_parts.each do |part|
      parts.push part
      path = full_path parts.join('/')
      if ::File.symlink? path
        raise SecurityError.new( "Cannot follow symlink: #{path.inspect}" )
      end
    end
  end

  # Shorthand for opening a file belonging to the share.
  def open_file partial, mode='rb'
    full = full_path partial
    check_path full

    fp = ::File.open full, mode
    return fp unless block_given?

    begin
      return yield fp
    ensure
      fp.close
    end
  end

  # Get the full path to a file in the share.
  def full_path partial
    full = "#{path}/#{partial}"

    full
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

  # Ask to be notified about changes to any files in this share.
  def subscribe &block
    @subscribers << block
  end

  def delete!
    @db.delete_database!
  end

  private
  # Notify subscribers about changes to a file
  def notify file
    raise "Nil file" unless file
    @subscribers.each do |block|
      block.call file
    end
  end
end
