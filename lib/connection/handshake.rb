class Connection
  module Handshake
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
        @level = starttls[:access].to_sym
      end

      @tcp_socket = @socket

      psk = (@code || @share).key :psk, @level

      if ENV['NO_ENCRYPTION']
        # For testing, perhaps because GnuTLS isn't available
        @socket = @tcp_socket

        if @incoming
          send :fake_tls_handshake, key: Base64.encode64(psk)
        else
          fake = recv :fake_tls_handshake
          raise "Invalid PSK: #{fake.inspect}" unless Base64.decode64(fake[:key])== psk
        end
      else
        @socket = gunlock {
          if @incoming
            GnuTLS::Server.new @socket, psk
          else
            GnuTLS::Socket.new @socket, psk
          end
        }
      end

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
        Log.debug "Sent key exchange"
        recv :keys_acknowledgment
      else
        msg = recv :keys
        if share = Shares.by_id(msg[:share_id])
          if share.path != @code.path
            Log.warn "#{share.path} and #{@code.path} have the same share_id"
            share = nil
          else
            Log.warn "Doing key_exchange again for an existing share #{share.path}"
          end
        end

        share ||= Share.new msg[:share_id]
        @share = share

        share.path = @code.path
        share.peer_id = @code.peer_id

        share.access_level = msg[:access_level]
        share.set_key :rsa, :read_write, msg[:read_write][:rsa]
        share.set_key :rsa, :read_only, msg[:read_only][:rsa]

        share.set_key :psk, :read_write, msg[:read_write][:psk]
        share.set_key :psk, :read_only, msg[:read_only][:psk]
        share.set_key :psk, :untrusted, msg[:untrusted][:psk]

        Shares.add share
        Log.debug "New share created"
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
  end

  def my_peer_id
    if @share
      @share.peer_id
    else
      @code.peer_id
    end
  end
end
