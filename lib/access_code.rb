# Class to represent a single access code.
#
# This class acts mostly like the Share class

require 'base32'
require 'luhn_check'
require 'digest/sha2'
require 'securerandom'

class AccessCode
  attr_accessor :peer_id

  def initialize payload
    @payload = payload
    @peer_id = SecureRandom.hex 16
  end

  def access_level
    :unknown
  end

  def self.create
    payload = SecureRandom.random_bytes 16
    self.new payload
  end

  def self.parse str
    raise "Wrong length, should be 37 characters" unless str.size == 37

    raise "Missing 'CLEARSKIES' prefix" unless str =~ /\ACLEARSKIES/

    # remove check digit
    str = LuhnCheck.verify str

    raise "Fails Luhn_mod_N check" unless str

    # remove CLEA
    str = str[4..-1]

    binary = Base32.decode str

    # remove "\x8C\x94\x82\x48"
    payload = binary[4..-1]

    self.new payload
  end

  def id
    @id ||= Digest::SHA256.hexdigest(@payload)
  end

  def to_s
    LuhnCheck.generate('CLEA' + Base32.encode("\x8C\x94\x82\x48" + @payload))
  end
end
