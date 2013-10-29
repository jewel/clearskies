require 'ffi'

module GnuTLS
  extend FFI::Library
  ffi_lib 'gnutls'

  # functions
  attach_function :gnutls_init, [:pointer, :int], :int
  attach_function :deinit, :gnutls_deinit, [:pointer], :void
  attach_function :priority_set_direct, :gnutls_priority_set_direct,
    [:pointer, :string, :pointer], :int

  def self.init(server_type)
    ptr = FFI::MemoryPointer.new :pointer
    gnutls_init(ptr, server_type)
    Session.new(ptr)
  end

  def self.init_client
    init(2)
  end

  def self.init_server
    init(1)
  end

  class Session
    def initialize(ptr)
      @session = ptr
    end

    def priority=(priority_str)
      GnuTLS.priority_set_direct(@session, priority_str, nil)
    end
  end

end

session = GnuTLS.init_client
session.priority = "PERFORMANCE:+ANON-ECDH:+ANON-DH"
