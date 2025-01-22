def transform(data)
  data.fish = data.fish_type.map do |fish_type|
    result = cached_content(key: [fish_type]) do
      "#{fish_type} fish"
    end.strip   # because test file ends with newline
  end

  data
end
