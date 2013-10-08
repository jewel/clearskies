# A permahash will often have values that are hashes or objects.  This provides
# a simple mechanism to cause them to save automatically.

class Permahash
  module Saveable
    def on_save &block
      @saver = block
    end

    def save!
      raise "#{self} cannot be saved, it has not been added to a database" unless @saver
      @saver.call
    end
  end
end
