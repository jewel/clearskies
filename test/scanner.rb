require 'minitest/autorun'

require 'tmpdir'

ENV['CLEARSKIES_DIR'] = Dir.mktmpdir

require 'fileutils'
require 'scanner'
require 'shares'
require 'share'

def create_files dir
  files= %w{ tmp1 tmp2 tmp3 }.map { |f| dir + '/' + f }

  # create some share files
  files.each do |f|
    File.binwrite f, "boring content in #{f}\n"
  end
  files
end

describe Scanner, "finds files" do
  before do
    @tmpdir = Dir.mktmpdir
    @share = Share.create @tmpdir
    Shares.add @share
  end

  after do
    #FileUtils.rm_rf(@tmpdir) # FIXME breaks the hasher
    Shares.remove @share
  end

  it "should find existing files" do
    files = create_files @tmpdir

    Scanner.start false

    sleep 3

    @share.map{|f| @share.full_path f.path }.sort.must_equal files.sort
  end

  it "should detect new files" do
    Scanner.start
    sleep 3
    files = create_files @tmpdir
    sleep 3
    @share.map{|f| @share.full_path f.path }.sort.must_equal files.sort
  end

  it "should detect deleted files" do
    files = create_files @tmpdir

    Scanner.start

    sleep 3

    File.delete files.pop

    sleep 1

    @share.map{|f| @share.full_path f.path }.sort.must_equal files.sort
  end
end
