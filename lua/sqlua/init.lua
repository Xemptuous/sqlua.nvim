local utils = require("sqlua.utils")
local Connection = require("sqlua.connection")
local UI = require("sqlua.ui")

local M = {}

ROOT_DIR = utils.concat({
    vim.fn.stdpath("data"),
    "sqlua"
})
DEFAULT_CONFIG = {
	db_save_location = utils.concat({ ROOT_DIR, "dbs" }),
	connections_save_location = utils.concat({ ROOT_DIR, "connections.json" }),
	default_limit = 200,
    load_connections_on_start = true,
    syntax_highlighting = false,
	keybinds = {
		execute_query = "<leader>r",
		activate_db = "<C-a>",
	}
}

M.setup = function(opts)
	local config = vim.tbl_deep_extend("force", DEFAULT_CONFIG, opts or {})

	-- creating root directory
	vim.fn.mkdir(ROOT_DIR, "p")

	-- creating config json
    local connections_file = utils.concat({
        vim.fn.stdpath("data"),
        "sqlua",
        "connections.json"
    })
	if vim.fn.filereadable(connections_file) == 0 then
		Connection.write({})
	end

	-- main function to enter the UI
	vim.api.nvim_create_user_command("SQLua", function(args)
		UI:setup(config)
		UI.initial_layout_loaded = true

        local cons = Connection.read()
        for _, con in pairs(cons) do
            local name, url = con["name"], con["url"]
            vim.fn.mkdir(ROOT_DIR .. "/" .. name, "p")
            local connection = Connection.setup(name, url)
            if config.load_connections_on_start and connection then
                connection:connect()
            end
            UI.dbs[name] = connection
        end

		-- UI.connections_loaded = true
		if UI.num_dbs > 0 then
			vim.api.nvim_win_set_cursor(UI.windows.sidebar, { 2, 2 })
		end
        UI:refreshSidebar()
	end, { nargs = "?" })

	vim.api.nvim_create_user_command("SQLuaAddConnection", function()
		-- TODO: add floating window to edit connections file on the spot
		local url = vim.fn.input("Enter the connection url: ")
		-- TODO: verify url string
		local name = vim.fn.input("Enter the name for the connection: ")
		Connection.add(url, name)
		local dbs = utils.getDatabases(config.connections_save_location)
		for _, db in pairs(dbs) do
            local connection = Connection.setup(db.name, db.url)
            if config.load_connections_on_start and connection then
                connection:connect()
            end
		end
		UI:refreshSidebar()
		if UI.num_dbs > 0 then
			vim.api.nvim_win_set_cursor(UI.windows.sidebar, { 2, 2 })
		end
	end, {})
end

return M
