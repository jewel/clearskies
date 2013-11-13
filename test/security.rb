require 'minitest/autorun'

require 'tmpdir'
require 'fileutils'

require_relative '../lib/share'

ENV['CLEARSKIES_DIR'] = conf = Dir.mktmpdir

dest = "#{conf}/lard"

test_file = "#{dest}/foo"

FileUtils.mkdir_p dest
File.binwrite test_file, 'ha ha ha'

share = Share.create dest

describe Share do
  it "allows access to normal files" do
    share.check_path test_file
  end

  it "allows access to files that do not yet exist" do
    share.check_path "#{dest}/bar"
    share.check_path "#{dest}/bar/baz"
  end

  it "doesn't allow absolute paths" do
    proc {
      share.check_path "/etc/passwd"
    }.must_raise SecurityError
  end

  it "doesn't allow relative paths" do
    proc {
      share.open_file "../../../etc/passwd"
    }.must_raise SecurityError

    proc {
      share.open_file "./../../../etc/passwd"
    }.must_raise SecurityError
  end

  it "won't follow symlinks" do
    File.symlink "/etc/passwd", "#{dest}/passwd"

    proc {
      share.open_file "passwd"
    }.must_raise SecurityError
  end

  it "won't follow symlinked directories" do
    File.symlink "/etc", "#{dest}/etc"

    proc {
      share.open_file "etc/passwd"
    }.must_raise SecurityError
  end
end
