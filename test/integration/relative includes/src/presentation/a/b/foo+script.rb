require_relative '../_bar'

def build
  render(content: func_from_bar(12))
end
