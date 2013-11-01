require 'minitest/autorun'
require 'tempfile'

require_relative '../lib/permahash'

def new_path
  path = Tempfile.new('clearskies').path
  File.unlink path
  path
end

describe Permahash, "saves to disk" do
  describe "when used in-memory" do
    before do
      @path = new_path
      @db = Permahash.new @path
    end

    after do
      File.unlink @path
    end

    it "should allow new keys" do
      @db[:foo] = 123
      @db[:lard] = 121
      @db[:foo].must_equal 123
    end

    it "should allow replacing keys" do
      @db[:bar] = 456
      @db[:bar] = 678
      @db[:bar].must_equal 678
    end

    it "should allow deleting keys" do
      @db[:baz] = 102
      @db.delete(:baz).must_equal 102
      @db[:baz].must_equal nil
    end

    it "should preserve arbitrary objects" do
      class Foo
        attr_accessor :v, :j
      end
      @db[:obj] = { :test_key => "test_value" }
      @db[:obj].must_equal({:test_key => "test_value"})
      f = Foo.new
      f.v = "v"
      f.j = "j"
      @db[:foo_class] = f
      @db[:foo_class].v.must_equal f.v
      @db[:foo_class].j.must_equal f.j
    end
  end

  describe "when restored from disk" do
    before do
      @path = new_path
      @db = Permahash.new @path

      @db[:new] = 1
      @db[:replace] = 2
      @db[:replace] = 3
      @db[:deleted] = 4
      @db.delete :deleted

      # reopen
      @db.close
      @db = Permahash.new @path
    end

    after do
      File.unlink @path
    end

    it "should have new keys" do
      @db[:new].must_equal 1
    end

    it "should have replaced keys" do
      @db[:replace].must_equal 3
    end

    it "should not have deleted keys" do
      @db[:deleted].must_equal nil
    end
  end

  describe "when adding lots of keys" do
    it "should vacuum" do
      path = new_path
      db = Permahash.new path

      10_000.times do |i|
        db[:foo] = i
      end

      db.close

      db = Permahash.new path
      db[:foo].must_equal 9_999

      File.unlink path
    end
  end

  describe "when having a partial write" do
    it "should recover" do
      path = new_path
      db = Permahash.new path

      100.times do |i|
        db[:foo] = i
      end

      db.close

      File.truncate( path, File.size(path) - 5 )

      db = Permahash.new path
      db[:foo].must_equal 98
    end
  end

  describe "when given a bad file" do
    it "should raise an exception" do
      proc {
        Permahash.new "/etc/passwd"
      }.must_raise RuntimeError
    end
  end

  describe "when empty" do
    it "should save and restore normally" do
      path = new_path
      3.times do
        db = Permahash.new path
        db.close
      end
    end
  end
end
