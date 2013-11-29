# Information about files present on local storage

class Share
  File = Struct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted

  class File

    def self.create relpath
      file = Share::File.new
      file.path = relpath
      file.id = SecureRandom.hex 16
      file.key = SecureRandom.hex 32
      file
    end

    def <=> other
      self.path <=> other.path
    end

    def commit stat
      self.mode = stat.mode.to_s(8)
      self.mtime = [stat.mtime.to_i, stat.mtime.nsec]
      self.size = stat.size
      self.deleted = false
    end
  end
end
