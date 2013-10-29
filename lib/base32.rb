# This is a simple base32 implementation
#
# It is not efficient (as it doesn't need to be for ClearSkies usage)
#
# See RFC 4648.

module Base32

  # Encode a binary string into Base32 ASCII representation.  Note that for
  # clearskies, only strings with lengths divisible by 5 are needed.
  def self.encode str
    if str.size % 5 != 0
      raise "Base32 needs a string length divisible by 5"
    end

    # Convert to binary
    binary_str = str.unpack('B*')[0]

    # break into groups of 5 bits
    groups = binary_str.scan(/.{5}/)

    characters = groups.map do |group|
      val = group.to_i(2)
      self.chr val
    end

    characters.map(&:chr).join ''
  end

  # Get the numeric value for a character.  Here we do the non-standard
  # substitutions of "O" for "0" and "L" for "1" to help confused users.
  def self.ord char
    # Replace 0 with O and 1 with L
    char = 'O' if char == '0'
    char = 'L' if char == '1'
    case char
    when 'A'..'Z'
      char.ord - 'A'.ord
    when '2'..'9'
      char.ord - '2'.ord + 26
    else
      raise "Invalid character in base32: #{char.inspect}"
    end
  end

  # Get the character that an integer value should encode to.
  def self.chr val
    if val >= 0 && val < 26
      ('A'.ord + val).chr
    elsif val < 32
      ('2'.ord + val - 26).chr
    else
      raise "Invalid integer for base32: #{int}"
    end
  end

  # Decode a Base32 ASCII string into a binary string
  def self.decode str
    str = str.upcase
    res = String.new
    group = ""
    str.each_char do |c|
      binary = self.ord(c).to_s(2)
      binary = "0" + binary while binary.size < 5
      group << binary

      if group.size >= 8
        res << group[0..7].to_i(2)
        group = group[8..-1]
      end
    end
    res
  end
end
