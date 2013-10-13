require 'minitest/autorun'

require 'access_code'

describe AccessCode, "generating" do
  it "should start with CLEARSKIES" do
    AccessCode.create.to_s.must_match /\ACLEARSKIES/
  end

  it "should be 37 characters" do
    AccessCode.create.to_s.size.must_equal 37
  end

  it "should be parseable itself" do
    16.times do
      str = AccessCode.create.to_s
      code = AccessCode.parse str
      code.to_s.must_equal str
    end
  end

  it "should be unique" do
    codes = {}
    100.times do
      code = AccessCode.create.to_s
      codes.has_key?(code).must_equal false
      codes[code] = true
    end
  end
end
