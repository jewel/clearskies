require 'minitest/autorun'
require 'socket'

require_relative '../lib/upnp'

describe UPnP, 'port opener' do
  it 'opens a port' do
    listener = TCPServer.new '', 0
    port = listener.local_address.ip_port
    UPnP.open 'TCP', port, port
  end
end
