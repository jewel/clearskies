require 'minitest/autorun'
require 'minitest/mock'

require 'tmpdir'
require 'fileutils'

ENV['CLEARSKIES_DIR'] = Dir.mktmpdir

require 'scanner'
require 'log'

module Scanner
  class Share
    include Enumerable
    def initialize path
      @path=path
      @files = {}
    end

    def partial_path full_path
      Pathname.new(full_path).relative_path_from(Pathname.new(@path)).to_s
    end

    def full_path partial
      "#{@path}/#{partial}"
    end

    def check_path path; end
    def path; @path end
    def save key; end

    def [] key
      @files[key]
    end

    def []= key, value
      @files[key] = value
    end

    def each
      @files.each do |k,v|
        next if v.deleted
        yield v
      end
    end

    def self.create path
      Share.new path
    end

    def verify files
      @files.map{|k,v| full_path v.path }.sort.must_equal files.sort
    end

    def verify_deleted files
      # make sure we have record of these files
      (files-@files.map{|k,v| full_path v.path }).must_equal []
      files.each do |file|
        @files[partial_path file].deleted.must_equal true
      end
    end

    File = Struct.new :path, :utime, :size, :mtime, :mode, :sha256, :id, :key, :deleted
    class File
      def self.create path
        file = Share::File.new
        file.path = path
        file
      end
      def commit stat; end
    end
  end

  module Shares
    @shares = []
    def self.add share
      @shares.push share
    end

    def self.each &block
      @shares.each &block
    end

    def self.reset
      @shares = []
    end
  end

  module Hasher
    @files = []
    def self.start; end
    def self.resume; end
    def self.pause; end

    def self.push share, file
      @files.push share.full_path(file.path)
    end

    def self.verify files
      @files.sort.must_equal files.sort
    end

    def self.reset
      @files = []
    end
  end

  class SimpleThread
    def initialize name, &block
      block.call
    end
  end

  module ChangeMonitor
    @monitored = []
    def self.find
      return self
    end
    def self.on_change &block
      @on_change = block
    end
    def self.monitor path
      return if @monitored.include? path
      @monitored.push path
    end

    def self.change_file path
      @monitored.must_include File.dirname path
      @on_change.call path
    end

    def self.verify paths
      (paths - @monitored).empty?.must_equal true
    end

    def self.reset
      @monitored = []
    end
  end
end

def create_files dir
  files= %w{ tmp1 tmp2 tmp3 }.map { |f| dir + '/' + f }

  # create some share files
  files.each do |f|
    File.binwrite f, "boring content in #{f}\n"
  end
  files
end

describe Scanner, "scans shares" do
  before do
    @tmpdir = Dir.mktmpdir
    @share = Scanner::Share.create @tmpdir
    Scanner::Hasher.reset
    Scanner::Shares.reset
    Scanner::Shares.add @share
  end

  after do
    FileUtils.rm_rf(@tmpdir)
  end

  describe "interacts with ChangeMonitor" do
    it "should monitor the share" do
      Scanner.load_change_monitor
      Scanner.register_and_scan @share
      Scanner::ChangeMonitor.verify [@share.path]
    end

    it "should put detected files in share" do
      Scanner.load_change_monitor
      Scanner.register_and_scan @share
      files = create_files @tmpdir
      files.each { |f| Scanner::ChangeMonitor.change_file f }

      @share.verify files
    end
  end

  describe "performs operations on existing files" do
    it "should hash them" do
      files = create_files @tmpdir
      Scanner.register_and_scan @share
      Scanner::Hasher.verify files
    end

    it "should add them to share" do
      files = create_files @tmpdir
      Scanner.register_and_scan @share
      @share.verify files
    end
  end

  describe "performs operations on deleted files" do
    it "should mark deleted files" do
      files = create_files @tmpdir
      Scanner.register_and_scan @share
      deleted_file = files.pop
      File.delete deleted_file
      Scanner::ChangeMonitor.change_file deleted_file

      @share.verify_deleted [deleted_file]
    end
  end
end
