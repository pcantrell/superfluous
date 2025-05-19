class Array
  def start_with?(other)
    self[0...other.length] == other
  end
end

class Pathname
  def contains?(other)
    # TODO: This mishandles /a/foo and /a/fooo; the accurate version here is surprisingly slow:
    # Array(other.descend).start_with?(Array(self.descend))
    other.to_s.start_with?(self.to_s)
  end

  def strip_leading_slash
    if absolute?
      relative_path_from("/")
    else
      self
    end
  end

  def components
    ascend
      .map { |ancestor| ancestor.basename.to_s }
      .reverse
  end

  def self.from_components(components)
    last_absolute = components.rindex { |s| s.start_with?("/") } || 0
    self.new(components[last_absolute...].join("/"))
  end

  def gsub_in_components(*args, &block)
    if root? || parent.each_filename.first == ".."  # Recursion needs to stop for "/", "foo/bar", and "../foo"
      self
    else
      parent.gsub_in_components(*args, &block) +
        basename.to_s.gsub(*args) do
          yield Regexp.last_match
        end
    end
  end
end

class StringScanner
  def line_number
    string.byteslice(0, pos).count("\n") + 1  # inefficient, but… ¯\_(ツ)_/¯
  end
end
