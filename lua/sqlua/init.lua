local utils = require('sqlua.utils')
local Connection = require('sqlua.connection')
local UI = require('sqlua.ui')


local M = {}


ROOT_DIR = utils.concat { vim.fn.stdpath("data"), "sqlua" }
CONNECTIONS_FILE =  utils.concat {vim.fn.stdpath("data"), 'sqlua', 'connections.json'}
DEFAULT_CONFIG = {
  db_save_location = utils.concat { ROOT_DIR, "dbs" },
  connections_save_location = utils.concat {ROOT_DIR, 'connections.json'},
  default_limit = 200,
  keybinds = {
    execute_query = "<leader>r"
  },
  ddl_colors = {
    db = "",
    buffers = "",
    saved_queries = "",
    schemas = "",
    schema = "",
    table = "",
    saved_query = "",
    new_query = "",
    table_stmt = "",
  }
}


M.setup = function(opts)
  local config = vim.tbl_deep_extend('force', DEFAULT_CONFIG, opts or {})

  -- creating root directory
  vim.fn.mkdir(ROOT_DIR, 'p')

  -- creating config json
  if vim.fn.filereadable(CONNECTIONS_FILE) == 0 then
    Connection.write({})
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
    Connection.execute()
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

