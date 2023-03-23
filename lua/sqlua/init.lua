local utils = require('sqlua.utils')
local Connection = require('sqlua.connection')
local UI = require('sqlua.ui')
local RootDir = utils.concat { vim.fn.stdpath("data"), "sqlua" }

local M = {}


local DEFAULT_SETTINGS = {
  db_save_location = utils.concat { RootDir, "dbs" },
  connections_save_location = utils.concat {RootDir, 'connections.json'},
  default_limit = 200,
  keybinds = {
    execute_query = "<leader>r"
  }
}


M.setup = function(opts)
  config = vim.tbl_deep_extend('force', DEFAULT_SETTINGS, opts or {})
  -- utils.getDatabases(config['connections_save_location'])
  -- if opts == nil then
  --   M.setup = DEFAULT_SETTINGS
  -- else
  --   -- TODO: alter only modified settings
  --   M.setup = opts
  -- end

  -- creating root directory
  if vim.fn.isdirectory(RootDir) == 0 then
    vim.fn.mkdir(RootDir)
  end

  -- creating config json
  if vim.fn.filereadable(Connection.connections_file) == 0 then
    Connection:writeConnection({})
  end

  -- main function to enter the UI
  vim.api.nvim_create_user_command('SQLua', function(args)
    UI:setup(config)
    Connection:connect(args.args)
  end, {nargs = 1})

  vim.api.nvim_create_user_command('SQLuaExecute', function(mode)
    Connection:executeQuery()
  end, {nargs = 1})

  vim.keymap.set({"n", "v"},
    -- M.setup.keybinds.execute_query, ":<C-U>SQLuaExecute<CR>", {
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
    Connection:addConnection(url, name)
  end, {})
end


return M

