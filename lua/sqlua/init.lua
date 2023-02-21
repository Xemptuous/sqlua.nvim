Utils = require('sqlua.utils')

local M = {}

RootDir = Utils.concat { vim.fn.stdpath("data"), "sqlua" }

-- create main directory if not exists

local DEFAULT_SETTINGS = {
  db_save_location = Utils.concat {RootDir, "dbs"},
}

vim.api.nvim_add_user_command('SQLua', function()
  local db = require('sqlua-connections.db')
  local tbl = db.readConnectionConfig()
  if not tbl then
    db.writeConnectionConfig({})
    tbl = db.readConnectionConfig()
  end
  -- TODO: fix this call
  -- if not Utils.isDir(RootDir) then
    -- TODO: add windows and mac functionality
    -- os.execute("mkdir" .. RootDir)
  -- end
  P(tbl)
end)

M.setup = function(opts)
  if opts == nil then
    M.setup = DEFAULT_SETTINGS
  else
    M.setup = opts
  end
  P(M.setup)
end

-- M.setup({
--   first = "one",
--   second = "two",
--   non = "no"
-- })

return M

