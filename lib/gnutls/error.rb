class GnuTLS::Error < RuntimeError
  def initialize message, code=nil
    message << ": #{GnuTLS.strerror(code)}" if code
    super message
  end
end
