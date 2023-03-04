local utils = require('sqlua.utils')
local Connection = require('sqlua-connections.db')
local RootDir = utils.concat { vim.fn.stdpath("data"), "sqlua" }

local M = {}


local DEFAULT_SETTINGS = {
  db_save_location = utils.concat { RootDir, "dbs" },
  connections_save_location = utils.concat { RootDir, 'connections.json' }
}

-- for postgres
-- psql -U <username> -d <dbname> -c "<QUERY>"
-- OR psql <full url> -c "<query>"
vim.api.nvim_create_user_command('SQLua', function(args)
  Connection.connect(Connection, args.args)
  vim.keymap.set({"n", "v"}, "<leader>r", function() Connection:executeQuery() end, {noremap = true, silent = true})
end, {nargs = 1})


vim.api.nvim_create_user_command('SQLuaAddConnection', function()
  local url = vim.fn.input("Enter the connection url: ")
  -- verify url string
  local name = vim.fn.input("Enter the display name for the connection: ")
  Connection.addConnection(url, name)
end, {})


M.setup = function(opts)
  if opts == nil then
    M.setup = DEFAULT_SETTINGS
  else
    M.setup = opts
  end

  -- creating root directory
  if vim.fn.isdirectory(RootDir) == 0 then
    vim.fn.mkdir(RootDir)
  end

  -- creating config json
  if vim.fn.filereadable(Connection.connections_file) == 0 then
    Connection.writeConnection({})
  end
end


return M

