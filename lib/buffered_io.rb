# Add support for gets, puts, read, readpartial to an IO-like class.
#
# The class should have its own implementation of unbuffered_readpartial() and
# write().  It should create @buffer (as an empty string) as part of its
# initialization.

module BufferedIO
  def readpartial len
    # To keep things simple, always drain the buffer first
    if @buffer.size > 0
      amount = [len,@buffer.size].min
      slice = @buffer[0...amount]
      @buffer = @buffer[amount..-1]
      return slice
    end

    unbuffered_readpartial len
  end

  def gets
    loop do
      if index = @buffer.index("\n")
        slice = @buffer[0..index]
        @buffer = @buffer[(index+1)..-1]
        return slice
      end

      @buffer << unbuffered_readpartial(1024 * 16)
    end
  end

  def puts str
    write str + "\n"
  end

  def read len
    str = String.new
    while str.size < len
      str << readpartial( len - str.size )
    end
    str
  end
end
