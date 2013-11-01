require 'ffi'
require 'socket'

module GnuTLS
  extend FFI::Library
  ffi_lib 'gnutls'

  def self.tls_function(name, *args)
    attach_function name, :"gnutls_#{name}", *args
  end

  # types
  enum :credentials_type, [:GNUTLS_CRD_CERTIFICATE, 1,
                           :GNUTLS_CRD_ANON,
                           :GNUTLS_CRD_SRP,
                           :GNUTLS_CRD_PSK,
                           :GNUTLS_CRD_IA]
  # functions
  attach_function :gnutls_init, [:pointer, :int], :int
  tls_function :deinit, [:pointer], :void
  tls_function :priority_set_direct, [:pointer, :string, :pointer], :int
  tls_function :credentials_set, [:pointer, :credentials_type, :pointer], :int
  tls_function :anon_allocate_client_credentials, [:pointer], :int
  tls_function :psk_allocate_client_credentials, [:pointer], :int
  tls_function :transport_set_int2, [:pointer, :int, :int], :void
  tls_function :handshake, [:pointer], :int
  tls_function :handshake_set_timeout, [:pointer, :int], :void

  callback :log_function, [:int, :string], :void
  tls_function :global_set_log_level, [:int], :void
  tls_function :global_set_log_function, [:log_function], :void

  CLIENT = 1
  SERVER = 2

  def self.init(type)
    ptr = FFI::MemoryPointer.new :pointer
    gnutls_init(ptr, type)
    Session.new(ptr.read_pointer, type)
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

    def handshake_timeout=(ms)
      GnuTLS.handshake_set_timeout(@session, ms)
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
                  when :GNUTLS_CRD_PSK
                    "psk_allocate_#{client_or_server}_credentials"
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

GnuTLS.global_set_log_function Proc.new { |lvl,msg| puts "#{lvl} #{msg}" }
session = GnuTLS.init_client
session.priority = "PERFORMANCE:+ANON-ECDH:+ANON-DH"
x = session.credentials = :GNUTLS_CRD_PSK
session.socket = TCPSocket.new("localhost", 4443)
#session.handshake_timeout = 10000
puts session.handshake
