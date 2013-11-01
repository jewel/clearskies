require 'ffi'
require 'socket'

module GnuTLS
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

  def self.tls_function(name, *args)
    attach_function name, :"gnutls_#{name}", *args
  end

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

  def self.tls_function name, *args
    attach_function name, "gnutls_#{name}".to_sym, *args
  end

  # global functions
  tls_function :global_init, [], :void
  tls_function :global_set_log_level, [ :int ], :void
  tls_function :global_set_log_function, [ :log_function ], :void

  # functions
  attach_function :gnutls_init, [:pointer, :int], :int
  tls_function :deinit, [:pointer], :void
  tls_function :error_is_fatal, [:int], :int
  tls_function :priority_set_direct, [:pointer, :string, :pointer], :int
  tls_function :credentials_set, [:pointer, :credentials_type, :pointer], :int
  tls_function :anon_allocate_client_credentials, [:pointer], :int
  tls_function :psk_allocate_client_credentials, [:pointer], :int
  tls_function :psk_allocate_server_credentials, [:pointer], :int
  tls_function :psk_set_client_credentials, [:pointer, :string, Datum, :psk_key_type ], :int
  tls_function :handshake, [:pointer], :int
  # tls_function :handshake_set_timeout, [:pointer, :int], :void

  callback :log_function, [:int, :string], :void
  tls_function :global_set_log_level, [:int], :void
  tls_function :global_set_log_function, [:log_function], :void
  tls_function :strerror, [:int], :string

  CLIENT = 1
  SERVER = 2

  class Error < RuntimeError
    def initialize message, code=nil
      message << ": #{GnuTLS.strerror(code)}" if code
      super message
    end
  end

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

      self.priority = "+PSK"
    end

    def handshake
      loop do
        res = GnuTLS.handshake(@session)
        break if res == 0

        if GnuTLS.error_is_fatal(res)
          raise Error.new("failed handshake", res) unless res.zero?
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

      @recv_data = Proc.new do |_, data, maxlen|

      end

      @send_data = Proc.new do |_, data, len|
        d = @socket.readpartial
        data.read_buffer(d)

        d.len
      end
    end

    def client_or_server
      @type == SERVER ? "server" : "client"
    end

    def psk= val
      creds = FFI::MemoryPointer.new :pointer

      allocator = "psk_allocate_#{client_or_server}_credentials"

      res = GnuTLS.send allocator, creds
      raise "Cannot allocate credentials" unless res == 0

      # Make sure that the string data won't be garbage collected
      # FIXME is this necessary?
      @psk = val
      psk = Datum.new
      psk[:data] = FFI::MemoryPointer.from_string(@psk)
      psk[:size] = val.size

      setter = "psk_set_#{client_or_server}_credentials"

      res = GnuTLS.send setter, creds.read_pointer, "Bogus", psk, :PSK_KEY_RAW
      raise "Can't #{setter}" unless res == 0

      res = GnuTLS.credentials_set @session, :CRD_PSK, creds.read_pointer
      raise "Can't credentials_set with PSK" unless res == 0

      val
    end

    def deinit
      GnuTLS.deinit(@session)
    end
  end

end

GnuTLS.global_set_log_function Proc.new { |lvl,msg| puts "#{lvl} #{msg}" }
session = GnuTLS.init_client
GC.disable
STDERR.sync = true
STDOUT.sync = true

GnuTLS.global_init
GnuTLS.global_set_log_level 9

session = GnuTLS.init_client
session.psk = "abcd"
session.socket = TCPSocket.new("localhost", 4443)
session.handshake
