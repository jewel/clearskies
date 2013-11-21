# Implementation of the Luhn mod N algorithm for base32, as used by clearskies

module LuhnCheck
  # Create check digit for string, and return string + check digit
  def self.generate str
    factor = 2
    sum = 0
    n = 32
    str.upcase.reverse.each_char do |char|
      addend = factor * Base32.ord(char)
      factor = (factor == 2) ? 1 : 2
      addend = addend / n + addend % n
      sum += addend
    end

    remainder = sum % n
    check_digit = (n - remainder) % n
    str + Base32.chr(check_digit)
  end

  # Verify that the input has a valid luhn check; if it does, return the string
  # without the check digit, otherwise return false
  def self.verify str
    data = str[0..-2]
    generate(data) == str.upcase && data
  end
end
