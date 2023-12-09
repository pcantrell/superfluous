(1...4).each do |n|
  render(n: 2 ** 2 ** n, content: "*" * (2 ** 2 ** n))
end
