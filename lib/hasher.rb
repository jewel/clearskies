# Worker to hash files on the local filesystem.  Clearskies only hashes one
# file at a time, to reduce system utilization as low as possible.
#
# Files are fed to Hasher from Scanner.  Scanner will pause Hasher when it's
# doing a directory-tree scan, as to not create too much I/O load.

module Hasher
  def self.start
    return if @worker
    @worker = SimpleThread.new 'hasher' do
      # FIXME Reduce thread priority even further than the rest of the daemon
      work
    end
    @hash_queue = Queue.new

    @paused = false
  end

  def self.push share, file
    @hash_queue.push [share, file]
  end

  def self.pause
    @paused = true
  end

  def self.resume
    @paused = false
    @worker.wakeup if @worker
  end

  private
  def self.work
    Shares.each do |share|
      share.each do |file|
        next if file.sha256
        @hash_queue.push [share, file]
      end
    end

    if @hash_queue.size > 0
      Log.info "Hasher has #{@hash_queue.size} files to hash"
    end

    loop do
      share, file = gunlock { @hash_queue.shift }
      next if file.sha256
      Log.info "Hashing #{file.path}"

      hash = hash_file share.full_path(file.path)

      Log.debug "Hashed #{file.path} to #{hash[0..8]}..."
      file.sha256 = hash
      share.save file.path
    end
  end

  def self.hash_file path
    digest = Digest::SHA256.new
    File.open path, 'rb' do |f|
      loop do
        gunlock {
          data = f.read(1024 * 512)
          if data.nil? # EOF
            return digest.hexdigest
          end
          digest << data
        }

        Thread.stop if @paused
      end
    end
  end
end
