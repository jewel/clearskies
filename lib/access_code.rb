# Class to represent a single access code.
#
# See protocol/core.md for an explanation of access codes.

require 'base32'
require 'luhn_check'
require 'digest/sha2'
require 'securerandom'

# This class converts the access code to a textual representation and can also
# parse that representation.
class AccessCode

  # Create an AccessCode object from existing key material
  #
  # payload  -  a binary string containing the access code's key
  def initialize payload
    @payload = payload
  end

  # Create a new Access Code object
  def self.create
    payload = SecureRandom.random_bytes 7
    self.new payload
  end

  # Parse an access code in ASCII format.
  # These are BASE32 encoded.
  def self.parse str
    raise "Wrong length, should be 17 characters, not #{str.size} characters" unless str.size == 17

    str.upcase!

    raise "Missing 'SYNC' prefix" unless str =~ /\ASYNC/

    # remove check digit
    str = LuhnCheck.verify str

    raise "Fails Luhn_mod_N check" unless str

    binary = Base32.decode str

    # Remove "\x96\x1A\x2B"

    payload = binary[3..-1]

    self.new payload
  end

  # Get the ID of the access code.  This is similar to the "Share ID" of a
  # share, and is used to locate other nodes that have the same access code.
  def id
    @id ||= Digest::SHA256.hexdigest(@payload)
  end

  # Get base32 representation of the access code, for sharing with other
  # people.
  def to_s
    LuhnCheck.generate(Base32.encode("\x96\x1A\x2B" + @payload))
  end

  # Get the key material for the access code.  This asks for the desired
  # access_level so that it behaves in a similar way to the Share class, but
  # the access_level of an AccessCode is always "unknown".
  def key access_level
    raise "Invalid access level" unless access_level == :unknown
    @payload
  end

  # Get the access_level of the Access Code.  This is always "unknown", since
  # access codes don't contain any information about the access level they will
  # represent.
  def access_level
    :unknown
  end
end
