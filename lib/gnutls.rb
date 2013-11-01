require 'ffi'
require 'socket'

# See https://defuse.ca/gnutls-psk-client-server-example.htm

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
  callback :push_function, [:pointer, :pointer, :size_t], :size_t
  callback :pull_function, [:pointer, :pointer, :size_t], :size_t

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

  tls_function :transport_set_push_function, [:pointer, :push_function], :void
  tls_function :transport_set_pull_function, [:pointer, :pull_function], :void
  tls_function :handshake, [:pointer], :int
  tls_function :record_recv, [:pointer, :pointer, :size_t], :int
  tls_function :record_send, [:pointer, :pointer, :size_t], :int
  # tls_function :handshake_set_timeout, [:pointer, :int], :void

  tls_function :global_set_log_level, [:int], :void
  tls_function :global_set_log_function, [:log_function], :void
  tls_function :strerror, [:int], :string

  SERVER = 1
  CLIENT = 2

  class Error < RuntimeError
    def initialize message, code=nil
      message << ": #{GnuTLS.strerror(code)}" if code
      super message
    end
  end

  def self.init type
    ptr = FFI::MemoryPointer.new :pointer
    gnutls_init(ptr, type)
    ptr.read_pointer
  end

  class Session
    def initialize ptr, direction
      @session = ptr
      @direction = direction
      # FIXME this isn't quite the right priority string
      self.priority = "SECURE128:-VERS-SSL3.0:-VERS-TLS1.0:-ARCFOUR-128:+PSK:+DHE-PSK"
      # FIXME create ephemeral DH parameters
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

      GnuTLS.transport_set_pull_function @session, Proc.new { |_, data, maxlen|
        d = @socket.readpartial maxlen
        data.write_bytes d

        d.size
      }

      GnuTLS.transport_set_push_function @session, Proc.new { |_, data, len|
        str = data.read_bytes len
        @socket.write str

        str.size
      }

      handshake
    end

    def psk= val
      creds = FFI::MemoryPointer.new :pointer

      allocator = "psk_allocate_#{@direction}_credentials"

      res = GnuTLS.send allocator, creds
      raise "Cannot allocate credentials" unless res == 0

      # Make sure that the string data won't be garbage collected
      # FIXME is this necessary?
      @psk = val
      psk = Datum.new
      psk[:data] = FFI::MemoryPointer.from_string(@psk)
      psk[:size] = val.size

      setter = "psk_set_#{@direction}_credentials"

      res = GnuTLS.send setter, creds.read_pointer, "Bogus", psk, :PSK_KEY_RAW
      raise "Can't #{setter}" unless res == 0

      res = GnuTLS.credentials_set @session, :CRD_PSK, creds.read_pointer
      raise "Can't credentials_set with PSK" unless res == 0

      val
    end

    # FIXME Can we inherit from IO or something similar and have puts, gets,
    # etc?
    #
    # In other words, is there a module that will do the buffering for us?
    # What does StringIO do?
    def write str
      total = 0
      pointer = FFI::MemoryPointer.from_string str
      while total < str.size
        sent = GnuTLS.record_send @session, pointer + total, str.size - total
        if sent == 0
          # FIXME What does this mean?
          raise "Sent returned zero"
        elsif sent < 0
          # FIXME Is this a GNUTLS error or just the error from push?
          raise "Sent returned error"
        end
        remaining += sent
      end
    end

    def puts str
      write str
      write "\n"
    end

    def gets
    end

    def read len
      total = 0
      str = String.new
      while total < len
        GnuTLS.record_recv @session, etc
      end
    end

    def readpartial len
    end

    def deinit
      # FIXME How do we ensure this is called?
      GnuTLS.deinit(@session)
    end
  end

  class Socket < Session
    def initialize socket, psk
      ptr = GnuTLS.init CLIENT
      super ptr, :client
      self.psk = psk
      self.socket = socket
    end
  end

  class Server < Session
    def initialize socket, psk
      ptr = GnuTLS.init SERVER
      super ptr, :server
      self.psk = psk
      self.socket = socket
    end
  end
end

GnuTLS.global_set_log_function Proc.new { |lvl,msg| puts "#{lvl} #{msg}" }
GC.disable
STDERR.sync = true
STDOUT.sync = true

GnuTLS.global_init
GnuTLS.global_set_log_level 9

tcp_socket = TCPSocket.new "localhost", 4443
socket = GnuTLS::Socket.new tcp_socket, "abcd"
p socket.read 10
