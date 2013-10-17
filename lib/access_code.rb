# Class to represent a single access code.

require 'base32'
require 'luhn_check'
require 'digest/sha2'
require 'securerandom'

class AccessCode
  def initialize payload
    @payload = payload
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

  def key access_level
    raise "Invalid access level" unless access_level = :unknown
    @payload
  end

  def access_level
    :unknown
  end
end
