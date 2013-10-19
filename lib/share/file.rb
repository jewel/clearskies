# Information about files present on local storage

class Share
  File = Struct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted

  class File
    def <=> other
      self.path <=> other.path
    end
  end
end
