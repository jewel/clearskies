require 'minitest/autorun'

require_relative '../lib/simple_condition'

describe SimpleCondition do
  it "waits for signal" do
    condition_has_been_signaled = false
    condition = SimpleCondition.new
    SimpleThread.new 'trigger' do
      gsleep 0.1
      condition_has_been_signaled = true
      condition.signal
    end
    condition.wait
    condition_has_been_signaled.must_equal true
  end
end
