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
    payload = SecureRandom.random_bytes 7
    self.new payload
  end

  def self.parse str
    raise "Wrong length, should be 17 characters, not #{str.size} characters" unless str.size == 17

    raise "Missing 'SYNC' prefix" unless str =~ /\ASYNC/

    # remove check digit
    str = LuhnCheck.verify str

    raise "Fails Luhn_mod_N check" unless str

    binary = Base32.decode str

    # Remove "\x96\x1A\x2B"

    payload = binary[3..-1]

    self.new payload
  end

  def id
    @id ||= Digest::SHA256.hexdigest(@payload)
  end

  def to_s
    LuhnCheck.generate(Base32.encode("\x96\x1A\x2B" + @payload))
  end

  def key access_level
    raise "Invalid access level" unless access_level == :unknown
    @payload
  end

  def access_level
    :unknown
  end
end
