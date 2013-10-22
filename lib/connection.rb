# Represents a connection with another peer
#
# The full protocol is documented in ../protocol/core.md

require 'socket'
require 'thread'
require 'openssl'
require 'conf'
require 'message'
require 'id_mapper'

class Connection
  attr_reader :peer, :access, :software, :friendly_name

  # Create a new Connection and begin communication with it.
  #
  # Outgoing connections will already know the share it is communicating with.
  def initialize socket, share=nil, code=nil
    @share = share
    @code = code
    @socket = socket

    @incoming = !share && !code
    warn "Starting #{@incoming ? 'incoming' : 'outgoing'} connection with #{@socket.peeraddr[2]}"
  end

  def start
    @receiving_thread = Thread.new do
      warn "Shaking hands"
      handshake
      warn "Requesting manifest"
      request_manifest
      warn "Receiving messages"
      receive_messages
    end
  end

  # Attempt to make an outbound connection with a peer
  def self.connect share, code, ip, port
    warn "Opening socket to #{ip} #{port}"
    socket = TCPSocket.new ip, port
    warn "Opened socket to #{ip} #{port}"
    self.new socket, share, code
  end

  def on_disconnect &block
    @on_disconnect = block
  end

  def on_discover_share &block
    @on_discover_share = block
  end

  private

  def send type, opts={}
    if !type.is_a? Message
      message = Message.new type, opts
    else
      message = type
    end

    if @send_queue
      puts "Sending: #{message.inspect}"
      @send_queue.push message
    else
      message.write_to_io @socket
    end
  end

  def start_send_thread
    @send_queue = Queue.new
    @sending_thread = Thread.new { send_messages }
  end

  def recv type=nil
    loop do
      msg = Message.read_from_io @socket
      return msg if !type || msg.type.to_s == type.to_s
      warn "Unexpected message: #{msg[:type]}, expecting #{type}"
    end

    msg
  end

  def receive_messages
    loop do
      msg = recv
      puts "Received: #{msg.to_s}"
      # begin
        handle msg
      # rescue
      #   warn "Error handling message #{msg[:type].inspect}: #$!"
      # end
    end
  end

  def handle msg
    case msg.type
    when :get_manifest
      if msg[:version] && msg[:version] == @share.version
        send :manifest_current
        return
      end
      send_manifest
      @share.subscribe do |file|
        warn "Connection learned about a change to #{file.path}"
        send_update file
      end
    when :manifest_current
      receive_manifest @peer.manifest
      request_file
    when :manifest
      # FIXME this isn't being saved
      @peer.manifest = msg
      @peer.updates = []
      receive_manifest msg
      request_file
    when :update
      @peer.updates << msg
      @remaining.push msg[:file] if need_file? msg[:file]
      request_file
    when :move
      raise "Move not yet handled"
    when :get
      fp = File.open @share.full_path(msg[:path]), 'rb'
      res = Message.new :file_data, { path: msg[:path] }
      remaining = fp.size
      if msg[:range]
        fp.pos = msg[:range][0]
        res[:range] = msg[:range]
        remaining = msg[:range][1]
      end

      res.binary_payload do
        if remaining > 0
          data = fp.read [1024 * 256, remaining].max
          remaining -= data.size
          data
        else
          fp.close
          nil
        end
      end

      send res
    when :file_data
      # FIXME Make sure we're not writing outside the share (perhaps this could
      # be done by Share)
      dest = @share.full_path msg[:path]
      temp = "#{File.dirname(dest)}/.#{File.basename(dest)}.#$$.#{Thread.current.object_id}.!sync"

      metadata = nil
      @remaining.each do |file|
        metadata = file if msg[:path] == file[:path]
      end

      File.open temp, 'wb' do |f|
        while data = msg.read_binary_payload
          f.write data
        end
      end

      warn "connection creating #{dest}: #{metadata[:mtime].to_f}"
      File.utime Time.new.to_f, metadata[:mtime].to_f, temp

      File.rename temp, dest

      @remaining.delete_if do |file|
        file[:path] == msg[:path]
      end

      request_file
      # FIXME Notify the scanner of the file via the share so that it can be
      # updated immediately
    end
  end

  def send_update file
    return unless file.sha256
    send :update, {
      file: file_as_manifest(file),
    }
  end

  def file_as_manifest file
    if file[:deleted]
      obj = {
        path: file.path,
        utime: file.utime,
        deleted: true,
        id: file.id
      }
    else
      obj = {
        path: file.path,
        utime: file.utime,
        size: file.size,
        mtime: file.mtime,
        mode: file.mode,
        sha256: file.sha256,
        id: file.id,
        key: file.key,
      }
    end
  end

  def send_manifest
    msg = Message.new :manifest
    msg[:peer] = @share.peer_id
    msg[:version] = @share.version
    msg[:files] = []
    @share.each do |file|
      puts "Found file: #{file.inspect}"
      next unless file[:sha256]

      obj = file_as_manifest file

      msg[:files] << obj
    end

    send msg
  end

  def receive_manifest msg
    @files = msg[:files]
    @remaining = []
    @files.each do |file|
      @remaining.push file if need_file? file
    end
  end

  def need_file? file
    # FIXME we need to actually delete it if its deleted
    return false if file[:deleted]

    ours = @share[ file[:path] ]

    return false if ours && file[:utime] < ours[:utime]
    # FIXME We'd also want to skip it if there is a pending download of this
    # file from another peer with an even newer utime

    !ours || file[:sha256] != ours[:sha256]
  end

  def request_file
    file = @remaining.sample
    return unless file
    send :get, {
      path: file[:path]
    }
  end

  def send_messages
    while msg = @send_queue.shift
      msg.write_to_io @socket
    end
  end

  def handshake
    if @incoming
      send :greeting, {
        software: Conf.version,
        protocol: [1],
        features: []
      }
    else
      greeting = recv :greeting

      unless greeting[:protocol].member? 1
        raise "Cannot communicate with peer, peer only knows versions #{greeting[:protocol].inspect}"
      end

      send :start, {
        software: Conf.version,
        protocol: 1,
        features: [],
        id: (@code || @share).id,
        access: (@code || @share).access_level,
        peer: my_peer_id,
      }
    end

    if @incoming
      start = recv :start
      @peer_id = start[:peer]
      @access = start[:access].to_sym
      @software = start[:software]
      @share, @code = IDMapper.find start[:id]
      if !@share && !@code
        send :cannot_start
        close
      end

      if @share
        @level = greatest_common_access(@access, @share.access_level)
      else
        @level = :unknown
      end

      send :starttls, {
        peer: (@share || @code).peer_id,
        access: @level,
      }
    else
      starttls = recv :starttls
      @peer_id = starttls[:peer]
      @level = starttls[@level]
    end

    @tcp_socket = @socket

    # @socket = OpenSSL::SSL::SSLSocket.new @tcp_socket, ssl_context
    # FIXME OpenSSL doesn't support the mode we need, skipping for now.

    key_exchange if @code

    start_send_thread

    send :identity, {
      name: Conf.friendly_name,
      time: Time.new.to_i,
    }

    identity = recv :identity
    @friendly_name = identity[:name]

    # We now trust that the peer_id was right, since we couldn't have received
    # the encrypted :identity message otherwise
    @share.each_peer do |peer|
      @peer = peer if peer.id == @peer_id
    end

    unless @peer
      @peer = Peer.new
      @peer.id = @peer_id
      @share.add_peer @peer
    end

    @peer.friendly_name = @friendly_name

    time_diff = identity[:time] - Time.new.to_i
    if time_diff.abs > 60
      raise "Peer clock is too far #{time_diff > 0 ? 'ahead' : 'behind'} yours (#{time_diff.abs} seconds)"
    end
  end

  def request_manifest
    if @peer.manifest && @peer.manifest[:version]
      send :get_manifest, {
        version: @peer.manifest[:version]
      }
    else
      send :get_manifest
    end
  end

  def key_exchange
    if @share
      # FIXME This should take the intended access level of the code into account

      send :keys, {
        access: @share.access_level,
        share_id: @share.id,
        untrusted: {
          psk: @share.key( :psk, :untrusted ),
        },
        read_only: {
          psk: @share.key( :psk, :read_only ),
          rsa: @share.key( :rsa, :read_only ),
        },
        read_write: {
          psk: @share.key( :psk, :read_write ),
          rsa: @share.key( :rsa, :read_write ),
        },
      }
      warn "Sent key exchange"
      recv :keys_acknowledgment
    else
      msg = recv :keys
      @share = share = Share.new msg[:share_id]
      share.path = @code.path
      share.peer_id = @code.peer_id

      share.access_level = msg[:access_level]
      share.set_key :rsa, :read_write, msg[:read_write][:rsa]
      share.set_key :rsa, :read_only, msg[:read_only][:rsa]

      share.set_key :psk, :read_write, msg[:read_write][:psk]
      share.set_key :psk, :read_only, msg[:read_only][:psk]
      share.set_key :psk, :untrusted, msg[:untrusted][:psk]

      Shares.add share
      warn "New share created"
      send :keys_acknowledgment
    end
  end

  def greatest_common_access l1, l2
    levels = [:unknown, :untrusted, :read_only, :read_write]
    i1 = levels.index l1
    raise "Invalid access level: #{l1.inspect}" unless i1
    i2 = levels.index l2
    raise "Invalid access level: #{l2.inspect}" unless i2
    common = [i1, i2].min
    levels[common]
  end

  def my_peer_id
    if @share
      @share.peer_id
    else
      @code.peer_id
    end
  end

  def ssl_context
    context = OpenSSL::SSL::SSLContext.new :TLSv1
    context.key = (@code || @share).key @level
    context.ciphers = ['AES-128-CBC']
    context.tmp_dh_callback = Proc.new do
      share.tls_dh_key
    end

    context
  end
end
