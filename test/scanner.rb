require 'minitest/autorun'

require 'tmpdir'
require 'fileutils'
require 'pp'

Shares = []
class Share
  attr_accessor :storage
  def initialize path
    @path = path
    @storage = {}
  end

  def path
    @path
  end

  def [] path
    @storage[path]
  end

  def []= path, file
    @storage[path] = file
  end

  class File
    def initialize path
      @path = path
    end
  end
end

require 'scanner'

class TestScanner < MiniTest::Unit::TestCase
  def setup
    @tmpdir = Dir::mktmpdir
    Shares.push Share.new @tmpdir 
    @share_files = %w{ tmp1 tmp2 tmp3 }.map { |f| @tmpdir + '/' + f }

    # create some share files
    @share_files.each do |f|
      File.open(f,'w') {}
    end
  end

  def test_initial_scan
    Scanner.start
    sleep 1
    storage = Shares[0].storage
    assert storage.size == @share_files.size, "Scanner did not find all of the files.\nFound:\n  #{storage.keys.join("\n  ")}\nExpected:\n  #{@share_files.join("\n  ")}"
    assert storage.keys.sort == @share_files.sort , "Scanner found different files.\nFound:\n  #{storage.keys.join("\n  ")}\nExpected:\n  #{@share_files.join("\n  ")}"
  end
end
