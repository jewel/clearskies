
module Hasher

  def self.start
    return if @worker
    @worker = SafeThread.new 'hasher' do
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
      digest = Digest::SHA256.new
      Log.info "Hashing #{file.path}"

      gunlock {
        File.open share.full_path(file.path), 'rb' do |f|
          while data = f.read(1024 * 512)
            digest << data

            Thread.stop if @paused
          end
        end
      }

      Log.debug "Hashed #{file.path} to #{digest.hexdigest[0..8]}..."
      file.sha256 = digest.hexdigest
      share.save file.path
    end
  end
end
