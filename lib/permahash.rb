# In-memory hash structure, persisted to disk via log file

class PermaHash
  # Percent storage efficiency should reach before vacuuming
  DESIRED_EFFICIENCY = 0.25

  # Never vacuum if log has less than this many entries
  MINIMUM_VACUUM_SIZE = 1024

  def initialize path
    @path = path
    @hash = {}
    @logfile = File.open @path, 'ab'
    @logsize = 0
    if File.exists? path
      read_from_file
    end
  end

  # Pass some operations through
  def size
    @hash.size
  end

  def each &bl
    @hash.each &bl
  end

  def [] key
    @hash[key]
  end

  def []= key, val
    @hash[key] = val
    save 'r', key, val
  end

  def delete key
    @hash.delete key
    save 'd', key, val
  end

  private
  # Save an update to disk
  def save oper, key, val=nil
    keyd = Marshal.dump key
    vald = Marshal.dump val
    @logfile.puts "#{oper}:#{keyd.size}:#{vald.size}"
    @logfile.write keyd
    @logfile.write vald
    @logsize += 1

    # Vacuum if log has gotten too large
    return unless @logsize > MINIMUM_VACUUM_SIZE
    return unless @logsize > @hash.size * 1.to_f / DESIRED_EFFICIENCY
    vacuum
  end

  def read_from_file
    File.open( @path, 'rb' ) do |f|
      while !f.eof?
        command = f.gets
        oper, keysize, valsize = command.split ':'
        keysize = keysize.to_i
        valsize = valsize.to_i
        key = Marshal.load f.read(keysize)
        val = Marshal.load f.read(valsize)
        @logsize += 1
        case oper
        when 'r' # replace
          @hash[key] = val
        when 'd' # delete
          @hash.delete key
        end
      end
    end
  end

  def vacuum
    temp = @path + ".#$$.tmp"
    @logfile = File.open temp, 'wb'
    @logsize = 0
    @hash.each do |key,val|
      save 'r', key, val
    end
    File.rename temp, @path
    @logfile = File.open @path, 'ab'
  end
end
