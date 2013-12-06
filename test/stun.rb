require 'minitest/autorun'

require_relative '../lib/stun.rb'

SERVER_LIST = %w{
  stun.l.google.com:19302
  stun1.l.google.com:19302
  stun2.l.google.com:19302
  stun3.l.google.com:19302
  stun4.l.google.com:19302
  stun01.sipphone.com
  stun.ekiga.net
  stun.fwdnet.net
  stun.ideasip.com
  stun.iptel.org
  stun.rixtelecom.se
  stun.schlund.de
  stunserver.org
  stun.softjoys.com
  stun.voiparound.com
  stun.voipbuster.com
  stun.voipstunt.com
  stun.voxgratia.org
  stun.xten.com
}

describe STUN do
  it "can discover the public IP address and port" do
    SERVER_LIST.each do |server|
      STUN.bind server
    end
  end
end

