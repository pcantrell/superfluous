def transform(data)
  data.fish = data.fish_type.map do |fish_type|
    # cache("fish", fish_type:) do
      "#{fish_type} fish"
    # end
  end

  data
end
