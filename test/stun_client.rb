require 'minitest/autorun'

require_relative '../lib/stun_client'
require_relative '../lib/shared_udp_socket'

SERVER_LIST = %w{
  stun.l.google.com:19302
  stun.ekiga.net
}

describe STUNClient do
  SERVER_LIST.each do |server|
    it "can bind via #{server}" do
      socket = SharedUDPSocket.new
      stun = STUNClient.new socket

      addr, port = nil, nil
      stun.on_bind do |a,p|
        addr = a
        port = p
      end
      stun.send_bind_request server

      timeout = 2.0
      while timeout > 0 && !addr
        gsleep 0.1
        timeout -= 0.1
      end

      raise "STUN Timeout" unless addr

      addr.wont_be_nil
    end
  end
end

