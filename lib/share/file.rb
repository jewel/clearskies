# Information about files present on local storage

class Share
  File = Struct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted

  class File
    def <=> other
      self.path <=> other.path
    end

    def commit stat
      self.mode = stat.mode.to_s(8)
      self.mtime = stat.mtime
      self.size = stat.size
    end
  end
end
