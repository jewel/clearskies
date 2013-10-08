# In-memory hash structure, persisted to disk via log file
#
# We usually don't flush to disk, since the data being stored can be
# regenerated.

class Permahash
  # Percent storage efficiency should reach before vacuuming
  DESIRED_EFFICIENCY = 0.25

  # Never vacuum if log has less than this many entries
  MINIMUM_VACUUM_SIZE = 1024

  HEADER = "CLEARSKIES PERMAHASH v1"

  def initialize path
    @path = path
    @hash = {}
    # FIXME Use locking to ensure that we don't open the logfile twice
    @logsize = 0
    read_from_file if File.exists? path
    @logfile = File.open @path, 'ab'
    @logfile.puts HEADER if @logsize == 0
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
      first = f.gets.chomp
      raise "Invalid file header" unless first == HEADER

      bytes = 0

      while !f.eof?
        command = f.gets
        # If the last line is a partial line, we discard it
        unless f =~ /\n\Z/
          f.truncate bytes
          break
        end

        bytes += command.size

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
    @logfile.puts HEADER
    @hash.each do |key,val|
      save 'r', key, val
    end
    File.rename temp, @path
    @logfile = File.open @path, 'ab'
  end
end
