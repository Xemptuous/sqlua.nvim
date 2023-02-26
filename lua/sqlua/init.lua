local utils = require('sqlua.utils')
local DB = require('sqlua-connections.db')
local RootDir = utils.concat { vim.fn.stdpath("data"), "sqlua" }

local M = {}


local DEFAULT_SETTINGS = {
  db_save_location = utils.concat { RootDir, "dbs" },
  connections_save_location = utils.concat { RootDir, 'connections.json' }
}


vim.api.nvim_create_user_command('SQLua', function(name)
  local connection
  if name.fargs then
    connection = DB.connect(name.fargs[1])
  else
    connection = DB.connect()
  end
  print(connection)
end, {nargs = 1})


vim.api.nvim_create_user_command('SQLuaAddConnection', function()
  url = vim.fn.input("Enter the connection details: ")
  -- verify url string
  name = vim.fn.input("Enter the display name for the connection: ")
  DB.addConnection(url, name)
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
  if vim.fn.filereadable(DB.connections_file) == 0 then
    DB.writeConnection({})
  end
end


return M

