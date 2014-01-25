require_relative '../buffered_io'

class GnuTLS::Session
  include BufferedIO

  def initialize ptr, direction
    @session = ptr
    @direction = direction
    # FIXME this isn't quite the right priority string
    self.priority = "SECURE128:-VERS-SSL3.0:-VERS-TLS1.0:-ARCFOUR-128:+PSK:+DHE-PSK"
    # FIXME create ephemeral DH parameters and force DHE mode
    @buffer = String.new
  end

  def handshake
    loop do
      res = GnuTLS.handshake(@session)
      return if res == 0

      if GnuTLS.error_is_fatal(res)
        raise GnuTLS::Error.new("failed handshake", res) unless res.zero?
      else
        warn "handshake problem (status #{res})" unless res.zero?
      end
    end
  end

  def handshake_timeout=(ms)
    GnuTLS.handshake_set_timeout(@session, ms)
  end

  def priority=(priority_str)
    GnuTLS.priority_set_direct(@session, priority_str, nil)
  end

  def socket= socket
    @socket = socket

    @pull_function = Proc.new { |_, data, maxlen|
      d = nil
      begin
        d = @socket.readpartial maxlen
      rescue EOFError
        d = ""  # signal EOF, we'll catch it again on the other side
      end
      data.write_bytes d, 0, d.size

      d.size
    }

    @push_function = Proc.new { |_, data, len|
      str = data.read_bytes len
      @socket.write str

      str.size
    }

    GnuTLS.transport_set_pull_function @session, @pull_function

    GnuTLS.transport_set_push_function @session, @push_function

    handshake
  end

  def psk= val
    creds = nil

    FFI::MemoryPointer.new :pointer do |creds_out|
      allocator = "psk_allocate_#{@direction}_credentials"

      res = GnuTLS.send allocator, creds_out
      raise "Cannot allocate credentials" unless res == 0

      creds = creds_out.read_pointer
    end

    if @direction == :client
      psk = GnuTLS::Datum.new
      @psk_data = psk[:data] = str_to_buffer val
      psk[:size] = val.size

      setter = "psk_set_#{@direction}_credentials"

      res = GnuTLS.send setter, creds, "Bogus", psk, :PSK_KEY_RAW
      raise "Can't #{setter}" unless res == 0
    else
      @server_creds_function = Proc.new { |_,username,key_pointer|
        # ignore username

        psk = GnuTLS::Datum.new key_pointer
        psk[:data] = GnuTLS::LibC.malloc val.size
        psk[:data].write_bytes val, 0, val.size
        psk[:size] = val.size

        0
      }

      GnuTLS.psk_set_server_credentials_function creds, @server_creds_function
    end

    res = GnuTLS.credentials_set @session, :CRD_PSK, creds
    raise "Can't credentials_set with PSK" unless res == 0

    val
  end

  def write str
    total = 0

    pointer = str_to_buffer str

    while total < str.size
      sent = GnuTLS.record_send @session, pointer + total, str.size - total
      if sent == 0
        # FIXME What does this mean?
        raise "Sent returned zero"
      elsif sent < 0
        raise GnuTLS::Error.new( "cannot send", sent )
      end
      total += sent
    end

    pointer.free
    nil
  end

  def unbuffered_readpartial len
    buffer = FFI::MemoryPointer.new :char, len

    res = GnuTLS.record_recv @session, buffer, len
    if res == -9
      # This error is "A TLS packet with unexpected length was received."
      # This almost certainly means that the connection was closed.
      raise EOFError.new
    elsif res < 0
      raise GnuTLS::Error.new("can't readpartial", res) unless res.zero?
    elsif res == 0
      raise "recv got zero"
    end

    buffer.read_bytes res
  ensure
    buffer.free
  end
  private :unbuffered_readpartial

  def deinit
    # FIXME How do we ensure this is called?
    GnuTLS.deinit(@session)
  end

  private
  def str_to_buffer str
    # Note that this will get garbage collected, so keep a permanent reference
    # around if that is undesirable
    pointer = FFI::MemoryPointer.new(:char, str.size)
    pointer.write_bytes str
    pointer
  end
end
