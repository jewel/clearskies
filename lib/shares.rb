# A list of the active shares
#
require 'permahash'
require 'conf'

module Shares
  # A database to keep track of all the valid shares.
  # It contains path => share_id
  db_path = "#{Conf.data_dir}/shares.db"
  @db = Permahash.new db_path

  # Also keep references to the Share objects
  @shares = {}

  def self.each
    @db.each do |path,id|
      yield by_id(id)
    end
  end

  def self.by_path path
    if id = @db[path]
      return by_id id
    else
      nil
    end
  end

  def self.by_id id
    return nil unless @db.values.member? id
    @shares[id] ||= Share.new id
  end

  def self.create path, share
    @db[path] = share.id
    @shares[id] = share
  end
end
