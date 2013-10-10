# Information about files present on local storage

require 'permahash/saveable'

class Share
  File = Struct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted

  class File
    include Permahash::Saveable
  end
end
