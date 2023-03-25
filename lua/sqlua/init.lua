local utils = require('sqlua.utils')
local Connection = require('sqlua.connection')
local UI = require('sqlua.ui')


local M = {}


local RootDir = utils.concat { vim.fn.stdpath("data"), "sqlua" }
CONNECTIONS_FILE =  utils.concat {vim.fn.stdpath("data"), 'sqlua', 'connections.json'}
local DEFAULT_SETTINGS = {
  db_save_location = utils.concat { RootDir, "dbs" },
  connections_save_location = utils.concat {RootDir, 'connections.json'},
  default_limit = 200,
  keybinds = {
    execute_query = "<leader>r"
  }
}


M.setup = function(opts)
  local config = vim.tbl_deep_extend('force', DEFAULT_SETTINGS, opts or {})

  -- creating root directory
  if vim.fn.isdirectory(RootDir) == 0 then
    vim.fn.mkdir(RootDir)
  end

  -- creating config json
  if vim.fn.filereadable(CONNECTIONS_FILE) == 0 then
    Connection.writeConnection({})
  end

  -- main function to enter the UI
  vim.api.nvim_create_user_command('SQLua', function(args)
    UI:setup(config)
    local dbs = nil
    if args.args == "" then
      dbs = utils.getDatabases(config.connections_save_location)
      for _, db in pairs(dbs) do
        Connection.connect(db.name)
      end
    else
      dbs = utils.splitString(args.args, " ")
      for _, db in pairs(dbs) do
        Connection.connect(db)
      end
    end
    UI:refreshSidebar()
  end, {nargs = '?'})

  vim.api.nvim_create_user_command('SQLuaExecute', function(mode)
    Connection.executeQuery()
  end, {nargs = 1})

  vim.keymap.set({"n", "v"},
    config.keybinds.execute_query, function()
      local mode = vim.api.nvim_get_mode().mode
      vim.cmd(":SQLuaExecute "..mode.."<CR>")
      end, { noremap = true, silent = true }
  )

  vim.api.nvim_create_user_command('SQLuaAddConnection', function()
    -- TODO: add floating window to edit connections file on the spot
    local url = vim.fn.input("Enter the connection url: ")
    -- TODO: verify url string
    local name = vim.fn.input("Enter the name for the connection: ")
    Connection.add(url, name)
  end, {})
end


return M

