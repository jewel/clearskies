# A list of the active shares.
require_relative 'permahash'
require_relative 'conf'

module Shares
  # A database to keep track of all the valid shares.
  # It contains path => share_id
  db_path = "#{Conf.data_dir}/shares.db"
  @db = Permahash.new db_path

  # Also keep references to the Share objects
  @shares = {}

  # Iterate through all shares
  def self.each
    @db.each do |path,id|
      yield find_by_id(id)
    end
  end

  # Find a share by path, or return nil if not present.
  def self.find_by_path path
    if id = @db[path]
      return find_by_id id
    else
      nil
    end
  end

  # Find a share by id, or return nil if not present
  def self.find_by_id id
    return nil unless @db.values.member? id
    @shares[id] ||= Share.new id
  end

  # Add a new share to the database.
  def self.add share
    @db[share.path] = share.id
    @shares[share.id] = share
    Scanner.add_share share
  end

  # Remove a share from the database.
  def self.remove share
    @db.delete share.path
    @shares.delete share.id
  end
end
