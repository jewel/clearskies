class GnuTLS::Server < GnuTLS::Session
  def initialize socket, psk
    ptr = GnuTLS.init GnuTLS::SERVER
    super ptr, :server
    self.psk = psk
    self.socket = socket
  end
end
