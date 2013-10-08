require 'minitest/autorun'

require 'change_monitor/gem_inotify'

require 'tmpdir'
require 'fileutils'

SLEEP_LENGTH = 0.1

class TestGemInotify < MiniTest::Unit::TestCase
  def setup
    @cm = ChangeMonitor::RbInotify.new
    @tmpdir = Dir::mktmpdir

    @detected_changes = []
    @cm.on_change { |p| @detected_changes.push p } 

    @cm.monitor @tmpdir
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def test_create_modify_file
    newfile = @tmpdir + "/newfile"
    File.open(newfile, 'w') {}
    sleep SLEEP_LENGTH
    assert @detected_changes.include?(newfile),
      "Did not detect the creation of #{newfile}. Detected:\n #{@detected_changes}"

    @detected_changes = []
    File.open(newfile, 'w') { |f| f.puts "Some changes" }
    sleep SLEEP_LENGTH
    assert @detected_changes.include?(newfile),
      "Did not detect the creation of #{newfile}. Detected:\n #{@detected_changes}"
  end

  def test_create_dir
    newdir = @tmpdir + '/newdir'
    Dir.mkdir(newdir)
    sleep SLEEP_LENGTH
    assert @detected_changes.include?(newdir),
      "Did not detect the creation of directory #{newdir}. Detected:\n #{@detected_changes}"
  end
end
