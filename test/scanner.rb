require 'minitest/autorun'

ENV['CLEARSKIES_DIR'] = Dir::mktmpdir

require 'tmpdir'
require 'fileutils'
require 'scanner'
require 'shares'
require 'share'

class TestScanner < MiniTest::Unit::TestCase
  def setup
    @tmpdir = Dir::mktmpdir
    @share = Share.create @tmpdir
    Shares.add @share
    @share_files = %w{ tmp1 tmp2 tmp3 }.map { |f| @tmpdir + '/' + f }

    # create some share files
    @share_files.each do |f|
      File.open(f,'w') {}
    end
  end

  def test_initial_scan
    Scanner.start
    sleep 3 # FIXME Make the test finish sooner if they are scanned sooner
    assert @share.map{|f| @share.full_path f.path }.sort == @share_files.sort , "Scanner found different files.\nFound:\n  #{@share.map{|f| @share.full_path f.path}.join("\n  ")}\nExpected:\n  #{@share_files.join("\n  ")}"
  end
end
