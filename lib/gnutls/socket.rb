class GnuTLS::Socket < GnuTLS::Session
  def initialize socket, psk
    ptr = GnuTLS.init GnuTLS::CLIENT
    super ptr, :client
    self.psk = psk
    self.socket = socket
  end
end
