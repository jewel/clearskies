# FFI interface for GNUTLS.  At the time of writing, OpenSSL does not implement
# the DHE-PSK TLS modes, which are necessary for clearskies.
#
# See https://defuse.ca/gnutls-psk-client-server-example.htm

require 'ffi'
require 'socket'

# Open the module early so that subclasses can be created
module GnuTLS; end

require_relative 'gnutls/session'
require_relative 'gnutls/server'
require_relative 'gnutls/socket'
require_relative 'gnutls/error'

module GnuTLS
  # Connect to malloc.
  module LibC
    extend FFI::Library
    ffi_lib FFI::Library::LIBC
    attach_function :malloc, [:size_t], :pointer
  end

  extend FFI::Library

  loaded = false
  %w{gnutls gnutls.so.26 gnutls.so.28}.each do |lib|
    begin
      ffi_lib lib
      loaded = true
      break
    rescue LoadError
    end
  end
  raise "Cannot load GNUTLS" unless loaded

  # typedefs
  typedef :pointer, :session
  typedef :pointer, :creds
  typedef :pointer, :creds

  # types
  enum :credentials_type, [:CRD_CERTIFICATE, 1,
                           :CRD_ANON,
                           :CRD_SRP,
                           :CRD_PSK,
                           :CRD_IA]
  enum :psk_key_type, [
    :PSK_KEY_RAW,
    :PSK_KEY_HEX
  ]

  # structs
  class Datum < FFI::Struct
    layout :data, :pointer,
           :size, :uint
  end

  # callbacks
  callback :log_function, [:int, :string], :void
  callback :push_function, [:pointer, :pointer, :size_t], :size_t
  callback :pull_function, [:pointer, :pointer, :size_t], :size_t
  callback :psk_creds_function, [:session, :string, :pointer], :int

  def self.tls_function name, *args
    attach_function name, :"gnutls_#{name}", *args
  end

  # global functions
  tls_function :global_init, [], :void
  tls_function :global_set_log_level, [ :int ], :void
  tls_function :global_set_log_function, [ :log_function ], :void

  # functions
  attach_function :gnutls_init, [:pointer, :int], :int

  tls_function :deinit, [:session], :void
  tls_function :error_is_fatal, [:int], :int
  tls_function :priority_set_direct, [:session, :string, :pointer], :int
  tls_function :credentials_set, [:session, :credentials_type, :creds], :int
  tls_function :psk_allocate_client_credentials, [:pointer], :int
  tls_function :psk_allocate_server_credentials, [:pointer], :int
  tls_function :psk_set_client_credentials, [:creds, :string, Datum, :psk_key_type ], :int
  tls_function :psk_set_server_credentials_function, [:creds, :psk_creds_function], :int

  tls_function :transport_set_push_function, [:session, :push_function], :void
  tls_function :transport_set_pull_function, [:session, :pull_function], :void

  begin
    tls_function :transport_set_int, [:session, :int], :void
  rescue FFI::NotFoundError
  end

  tls_function :handshake, [:session], :int
  tls_function :record_recv, [:session, :pointer, :size_t], :int
  tls_function :record_send, [:session, :pointer, :size_t], :int
  # tls_function :handshake_set_timeout, [:pointer, :int], :void

  tls_function :global_set_log_level, [:int], :void
  tls_function :global_set_log_function, [:log_function], :void
  tls_function :strerror, [:int], :string

  SERVER = 1
  CLIENT = 2

  # Create a server or client, and return the pointer to the session struct
  def self.init type
    GnuTLS.global_init unless @global_initted
    @global_initted = true

    FFI::MemoryPointer.new :pointer do |ptr|
      gnutls_init(ptr, type)
      return ptr.read_pointer
    end
  end

  # Turn on GnuTLS logging
  def self.enable_logging
    @logging_function = Proc.new { |lvl,msg| puts "#{lvl} #{msg}" }
    GnuTLS.global_set_log_function @logging_function
    GnuTLS.global_set_log_level 9
  end
end
