require 'minitest/autorun'

require_relative '../lib/debouncer'

describe Debouncer do
  it 'handles just one event' do
    db = Debouncer.new "test1", 0.1
    res = 0
    db.call { res += 1 }
    res.must_equal 0
    gsleep 0.05
    res.must_equal 0
    gsleep 0.1
    res.must_equal 1
    gsleep 0.1
    res.must_equal 1
    db.shutdown
  end

  it 'handles many events' do
    db = Debouncer.new "test2", 0.1
    res = ""
    db.call { res << "a" }
    res.must_equal ""
    gsleep 0.05
    db.call { res << "b" }
    db.call { res << "c" }
    res.must_equal ""
    gsleep 0.05
    db.call { res << "d" }
    res.must_equal ""
    gsleep 0.05
    res.must_equal ""
    gsleep 0.1
    res.must_equal "d"
    gsleep 0.1
    res.must_equal "d"
    db.shutdown
  end

  it 'handles event with categories' do
    db = Debouncer.new "test3", 0.1
    a = 0
    b = 0

    db.call(:a) { a += 1 }
    db.call(:b) { b += 1 }
    a.must_equal 0
    b.must_equal 0
    gsleep 0.05
    a.must_equal 0
    b.must_equal 0
    gsleep 0.1
    a.must_equal 1
    b.must_equal 1
    gsleep 0.1
    a.must_equal 1
    b.must_equal 1
    db.shutdown
  end
end
