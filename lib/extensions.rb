class Array
  def start_with?(other)
    self[0...other.length] == other
  end
end

class Pathname
  def contains?(other)
    Array(other.descend).start_with?(Array(self.descend))
  end
end
