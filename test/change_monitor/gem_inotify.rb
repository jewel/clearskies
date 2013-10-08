require 'minitest/autorun'


require 'tmpdir'
require 'fileutils'
require 'timeout'

SLEEP_LENGTH = 0.1
TIMEOUT_LENGTH = 1

class TestGemInotify < MiniTest::Unit::TestCase
  def setup
    @tmpdir = Dir::mktmpdir
    begin
      require 'rb-inotify'
    rescue LoadError
      skip "rb-inotify not present"
    end
    require 'change_monitor/gem_inotify'
    @cm = ChangeMonitor::GemInotify.new

    @detected_changes = []
    @cm.on_change { |p| @detected_changes.push p } 

    @cm.monitor @tmpdir
  end

  def teardown
    FileUtils.rm_rf @tmpdir
  end

  def changed? path
    begin
      Timeout::timeout(TIMEOUT_LENGTH) {
        until @detected_changes.include? path 
          sleep SLEEP_LENGTH
        end
      }
    rescue ExitError
      #timed out
      return false
    end
    true
  end

  def test_create_modify_file
    newfile = @tmpdir + "/newfile"
    File.open(newfile, 'w') {}
    assert changed?(newfile),
      "Did not detect the creation of #{newfile}. Detected:\n #{@detected_changes}"

    @detected_changes = []
    File.open(newfile, 'w') { |f| f.puts "Some changes" }
    assert changed?(newfile),
      "Did not detect the creation of #{newfile}. Detected:\n #{@detected_changes}"
  end

  def test_create_dir
    newdir = @tmpdir + '/newdir'
    Dir.mkdir(newdir)

    assert changed?(newdir),
      "Did not detect the creation of directory #{newdir}. Detected:\n #{@detected_changes}"
  end
end
