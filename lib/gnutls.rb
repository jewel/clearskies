require 'ffi'
require 'socket'

module GnuTLS
  extend FFI::Library
  ffi_lib 'gnutls'

  # types
  enum :credentials_type, [:GNUTLS_CRD_CERTIFICATE, 1,
                           :GNUTLS_CRD_ANON,
                           :GNUTLS_CRD_SRP,
                           :GNUTLS_CRD_PSK,
                           :GNUTLS_CRD_IA]
  # functions
  attach_function :gnutls_init, [:pointer, :int], :int
  attach_function :deinit, :gnutls_deinit, [:pointer], :void
  attach_function :priority_set_direct, :gnutls_priority_set_direct,
    [:pointer, :string, :pointer], :int
  attach_function :credentials_set, :gnutls_credentials_set,
    [:pointer, :credentials_type, :pointer], :int
  attach_function :anon_allocate_client_credentials,
    :gnutls_anon_allocate_client_credentials,
    [:pointer], :int
  attach_function :transport_set_int2, :gnutls_transport_set_int2,
    [:pointer, :int, :int], :void
  attach_function :handshake, :gnutls_handshake, [:pointer], :int

  CLIENT = 1
  SERVER = 2

  def self.init(type)
    ptr = FFI::MemoryPointer.new :pointer
    gnutls_init(ptr.ptr, type) # FIXME
    Session.new(ptr, type)
  end

  def self.init_client
    init(CLIENT)
  end

  def self.init_server
    init(SERVER)
  end

  class Session
    def initialize(ptr, type)
      @session = ptr
      @type = type
    end

    def handshake
      ret = GnuTLS.handshake(@session)
      raise "handshake failed (status #{ret})" unless ret.zero?
    end

    def priority=(priority_str)
      GnuTLS.priority_set_direct(@session, priority_str, nil)
    end

    def credentials=(credentials_type)
      @credentials = allocate_credentials(credentials_type)
      GnuTLS.credentials_set(@session, credentials_type, @credentials)
    end

    def socket=(socket)
      GnuTLS.transport_set_int2(@session, socket.fileno, socket.fileno)
    end

    def allocate_credentials(credentials_type)
      ptr = FFI::MemoryPointer.new :pointer

      client_or_server = @type == SERVER ? "server" : "client"
      allocator = case credentials_type
                  when :GNUTLS_CRD_ANON
                    "anon_allocate_#{client_or_server}_credentials"
                  # TODO: fill in other types
                  else raise 'unknown credentials type'
                  end
      GnuTLS.send allocator, ptr
      ptr
    end
    private :allocate_credentials

    def deinit
      GnuTLS.deinit(@session)
    end
  end

end

session = GnuTLS.init_client
session.priority = "PERFORMANCE:+ANON-ECDH:+ANON-DH"
session.credentials = :GNUTLS_CRD_ANON
session.socket = TCPSocket.new("localhost", 4443)
session.handshake
