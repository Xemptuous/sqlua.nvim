local M = {}
require('utils')

M.setup = function(opts)
  print("Options:")
  P(opts)
end

M.setup({
  first = "one",
  second = "two",
  non = "no"
})

return M

