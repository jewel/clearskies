# Information 

require 'struct'
Share::File = Stuct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted

class Share::File
  include Permahash::Saveable

  def initialize
  end
end
