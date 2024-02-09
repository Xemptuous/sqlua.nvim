local utils = require("sqlua.utils")
---@class Connections
---module class for various methods
local Connections = {}
Connections.connections = {}

---@class Connection
---@field expanded boolean sidebar expansion flag
---@field num_schema integer number of schema in this db
---@field name string locally defined db name
---@field url string full url to connect to the db
---@field cmd string query to execute
---@field rdbms string actual db name according to the url
---@field last_query table<string> last query executed
---@field schema table<table<table>> nested schema design for this db
---the primary object representing a single connection to a rdbms by url
local Connection = {
	expanded = false,
	saved_queries_expanded = false,
	schemas_expanded = false,
	num_schema = 0,
	name = "",
	url = "",
	cmd = "",
	rdbms = "",
	last_query = {},
	schema = {},
	saved_queries = {},
}

RUNNING_JOBS = {}
CONNECTIONS_FILE = utils.concat({ vim.fn.stdpath("data"), "sqlua", "connections.json" })

---@param data table
---@return nil
---Gets the initial db structure for postgresql rdbms
-- function Connection:getPostgresSchema(data)
local function getPostgresSchema(data, con)
	con.rdbms = "postgres"
	local schema = utils.shallowcopy(data)
	table.remove(schema, 1)
	table.remove(schema, 1)
	table.remove(schema)
	table.remove(schema)
	table.remove(schema)
	local seen = {}
	for i, _ in ipairs(schema) do
		schema[i] = string.gsub(schema[i], "%s", "")
		schema[i] = utils.splitString(schema[i], "|")

		local schema_name = schema[i][1]
		local table_name = schema[i][2]
		if not seen[schema_name] then
			con.schema[schema_name] = {
				expanded = false,
				num_tables = 0,
				tables = {},
			}
			seen[schema_name] = true
		end
		if table_name ~= "-" then
			con.schema[schema_name].tables[table_name] = {
				expanded = false,
			}
			con.schema[schema_name].num_tables = con.schema[schema_name].num_tables + 1
		end
	end
end

local function refreshPostgresSchema(data, con)
	local schema = utils.shallowcopy(data)
	table.remove(schema, 1)
	table.remove(schema, 1)
	table.remove(schema)
	table.remove(schema)
	table.remove(schema)
	for i, _ in ipairs(schema) do
		schema[i] = string.gsub(schema[i], "%s", "")
		schema[i] = utils.splitString(schema[i], "|")

		local schema_name = schema[i][1]
		local table_name = schema[i][2]

		if not con.schema[schema_name] then
			con.schema[schema_name] = {
				expanded = false,
				num_tables = 0,
				tables = {},
			}
		end
		if table_name ~= "-" then
			if not con.schema[schema_name].tables[table_name] then
				con.schema[schema_name].tables[table_name] = {
					expanded = false,
				}
				con.schema[schema_name].num_tables = con.schema[schema_name].num_tables + 1
			end
		end
	end
	-- cleaner k:v version
	local final_schema = {}
	for _, tbl in ipairs(schema) do
		if not final_schema[tbl[1]] then
			final_schema[tbl[1]] = {}
		end
		final_schema[tbl[1]][tbl[2]] = ""
	end
	-- remove schema/tables that have been deleted since last refresh
	for s, _ in pairs(con.schema) do
		if s ~= "pg_catalog" and s ~= "information_schema" then
			if final_schema[s] == nil then
				con.schema[s] = nil
			else
				for t, _ in pairs(con.schema[s].tables) do
					if final_schema[s][t] == nil then
						con.schema[s].tables[t] = nil
					end
				end
			end
		end
	end
end

local function onRefresh(job_id, data, event, con, name)
	if event == "stdout" then
		refreshPostgresSchema(data, con)
	elseif event == "stderr" then
	elseif event == "exit" then
	else
	end
end

Connections.refreshSchema = function(Con)
	for _, connection in pairs(Connections.connections) do
		if connection["name"] == Con.name then
			local Queries = require("sqlua.queries.postgres")
			-- TODO: change based on active connection
			local query = string.gsub(Queries.SchemaQuery, "\n", " ")
			local name = connection.name
			local cmd = connection.cmd .. query
			table.insert(connection.last_query, query)

			local opts = {
				stdin = "null",
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(job_id, data, event)
					onRefresh(job_id, data, event, connection, name)
				end,
				on_data = function(job_id, data, event)
					onRefresh(job_id, data, event, connection, name)
				end,
				on_stderr = function(job_id, data, event)
					onRefresh(job_id, data, event, connection, name)
				end,
				on_exit = function(job_id, data, event)
					onRefresh(job_id, data, event, connection, name)
				end,
			}
			table.insert(RUNNING_JOBS, vim.fn.jobstart(cmd, opts))
			vim.fn.jobwait(RUNNING_JOBS, 5000)
			table.remove(RUNNING_JOBS, 1)
			-- Connections.connections[con.name] = con
			return connection
		end
	end
end

---@param data table
---@return nil
---Takes query output and creates a 'Results' window & buffer
local function createResultsPane(data)
	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	--TODO: new result window increments by 1 each time
	-- consider reusing same one per window
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, "ResultsBuf")
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_height(0, 10)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, data)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.cmd("goto 1")
	table.insert(require("sqlua.ui").buffers.results, buf)
	table.insert(require("sqlua.ui").windows.results, win)
end

---@param job_id integer
---@param data table
---@param event string<'stdout', 'stderr', 'exit'>
---@return nil
---Callback for general jobcontrol events
local function onEvent(job_id, data, event)
	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	local buf = vim.api.nvim_win_get_buf(win)
	if (event == "stdout") or (event == "stderr") then
		if data[1] == "" then
			return
		end
		if vim.fn.bufexists("ResultsBuf") == 1 then
			for _, buffer in pairs(vim.api.nvim_list_bufs()) do
				if vim.fn.bufname(buffer) == "ResultsBuf" then
					vim.api.nvim_buf_delete(buffer, { force = true, unload = false })
				end
			end
		end
		createResultsPane(data)
		vim.api.nvim_set_current_win(win)
		vim.api.nvim_win_set_buf(win, buf)
		vim.api.nvim_win_set_cursor(win, pos)
	end
end

---@param job_id integer
---@param data table
---@param event string<'stdout', 'stderr', 'exit'>
---@return nil
--Callback for Connection.connect() jobcontrol
local function onConnect(job_id, data, event, con)
	local connection = con
	if event == "stdout" then
		-- Connection:getPostgresSchema(data)
		con = getPostgresSchema(data, connection)
	elseif event == "stderr" then
	elseif event == "exit" then
		require("sqlua.ui"):add(connection)
	else
	end
end

---@param cmd string|nil
---@return nil
---Executes the given query (cmd).
---Optional 'mode' determines what is executed:
---  - 'n' - executes entire buffer
---  - 'v' - executes visual selection
---  - 'V' - executes visual line
---  - '^V' - executes visual block
Connections.execute = function(
	cmd, --[[optional mode string]]
	mode
)
	if not cmd or type(cmd) == "table" then
		local ui = require("sqlua.ui")
		if not ui.dbs[ui.active_db] then
			return
		end
		cmd = ui.dbs[ui.active_db].cmd
	end
	if not mode then
		mode = vim.api.nvim_get_mode().mode
	end

	local query = nil

	if mode == "n" then
		-- normal mode
		query = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	elseif mode == "V" then
		-- visual line mode
		esc_key = vim.api.nvim_replace_termcodes("<Esc>", false, true, true)
		vim.api.nvim_feedkeys(esc_key, "nx", false)
		local srow = vim.api.nvim_buf_get_mark(0, "<")[1]
		local erow = vim.api.nvim_buf_get_mark(0, ">")[1]
		if srow <= erow then
			query = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
		else
			query = vim.api.nvim_buf_get_lines(0, erow - 1, srow - 1, false)
		end
	elseif mode == "v" then
		-- visual mode
		local _, srow, scol, _ = unpack(vim.fn.getpos("."))
		local _, erow, ecol, _ = unpack(vim.fn.getpos("v"))
		if srow < erow or (srow == erow and scol <= ecol) then
			query = vim.api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
		else
			query = vim.api.nvim_buf_get_text(0, erow - 1, ecol - 1, srow - 1, scol, {})
		end
	elseif mode == "\22" then
		-- visual block mode
		local _, srow, scol, _ = unpack(vim.fn.getpos("."))
		local _, erow, ecol, _ = unpack(vim.fn.getpos("v"))
		local lines = vim.api.nvim_buf_get_lines(0, math.min(srow, erow) - 1, math.max(srow, erow), false)
		query = {}
		local start = math.min(scol, ecol)
		local _end = math.max(scol, ecol)
		for _, line in ipairs(lines) do
			table.insert(query, string.sub(line, start, _end))
		end
	end
	local opts = {
		stdout_buffered = true,
		stderr_buffered = true,
		on_exit = onEvent,
		on_stdout = onEvent,
		on_stderr = onEvent,
		on_data = onEvent,
	}
	-- removing pure comment lines
	for i, j in ipairs(query) do
		local cleaned = j:gsub("%s+", "")
		if cleaned:sub(1, 1) == "-" then
			if cleaned:sub(2, 2) then
				table.remove(query, i)
			end
		end
	end
	local command = cmd .. '"' .. table.concat(query, " ") .. '"'
	local job = vim.fn.jobstart(command, opts)
end

---@param name string
---@return nil
---Initializes the connection to the DB, and inserts into UI.
---Required for any operations on the given db.
Connections.connect = function(name)
	-- TODO: add async functionality without having to use jobwait
	local connections = Connections.read()
	for _, connection in pairs(connections) do
		if connection["name"] == name then
			local con = vim.deepcopy(Connection)
			con.name = name
			con.url = connection["url"]
			-- TODO: check url and change cli command appropriately
			con.cmd = "psql " .. connection["url"] .. " -c "
			local Queries = require("sqlua.queries.postgres")
			-- TODO: change based on active connection
			local query = string.gsub(Queries.SchemaQuery, "\n", " ")
			local cmd = con.cmd .. query
			table.insert(con.last_query, query)

			local opts = {
				stdin = "null",
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(job_id, data, event)
					onConnect(job_id, data, event, con)
				end,
				on_data = function(job_id, data, event)
					onConnect(job_id, data, event, con)
				end,
				on_stderr = function(job_id, data, event)
					onConnect(job_id, data, event, con)
				end,
				on_exit = function(job_id, data, event)
					onConnect(job_id, data, event, con)
				end,
			}
			table.insert(RUNNING_JOBS, vim.fn.jobstart(cmd, opts))
			vim.fn.jobwait(RUNNING_JOBS, 5000)
			table.remove(RUNNING_JOBS, 1)
			Connections.connections[con.name] = con
		end
	end
end

---@return table<string, string>
---Reads the connection.json file and returns content as a table
Connections.read = function()
	local content = vim.fn.readfile(CONNECTIONS_FILE)
	content = vim.fn.json_decode(vim.fn.join(content, "\n"))
	return content
end

---@param data table<string, string>
---@return nil
---Writes the given table to the connections.json file.
---table is expected to be in json format
Connections.write = function(data)
	local json = vim.fn.json_encode(data)
	vim.fn.writefile({ json }, CONNECTIONS_FILE)
end

---@param url string
---@param name string
---@return nil
---Adds the given url + name to the connections.json file
Connections.add = function(url, name)
	local file = Connections.read()
	table.insert(file, { url = url, name = name })
	vim.fn.mkdir(ROOT_DIR .. "/" .. name, "p")
	Connections.write(file)
end

return Connections
