local utils = require("sqlua.utils")

---@class Connections
local Connections = {}

---@class Schema
local Schema = {
    tables = {},
    num_tables = 0
}

---@class Connection
---@field files_expanded boolean sidebar expansion flag
---@field num_schema integer number of schema in this db
---@field name string locally defined db name
---@field url string full url to connect to the db
---@field cmd string query to execute
---@field rdbms string actual db name according to the url
---@field schema Schema nested schema design for this db
---@field files table all saved files in the local dir
---The primary object representing a single connection to a rdbms by url
local Connection = {
	files_expanded = false,
	num_schema = 0,
	name = "",
	url = "",
	cmd = "",
	rdbms = "",
	schema = {},
	files = {},
}

---@param data string
---@return table
--- Takes string results and transforms them to a table of strings
local function cleanData(data)
    local result = {}
    local i = 1
    for c in data:gmatch(string.format("([^%s]+)", '\n')) do
        result[i] = c
        i = i + 1
    end
    return result
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

---@param data table
---@return nil
function Connection:query(data)
	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	local buf = vim.api.nvim_win_get_buf(win)
    if data[1] == "" then
        return
    end
    if vim.fn.bufexists("ResultsBuf") == 1 then
        for _, buffer in pairs(vim.api.nvim_list_bufs()) do
            if vim.fn.bufname(buffer) == "ResultsBuf" then
                vim.api.nvim_buf_delete(buffer, {
                    force = true,
                    unload = false
                })
            end
        end
    end
    createResultsPane(data)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_cursor(win, pos)
end

---@param data table
---@return nil
---Gets the initial db structure for postgresql rdbms
function Connection:getPostgresSchema(data)
	self.rdbms = "postgres"
	local schema = utils.shallowcopy(data)
	table.remove(schema, 1)
	table.remove(schema, 1)
	table.remove(schema)

	for i, _ in ipairs(schema) do
		schema[i] = string.gsub(schema[i], "%s", "")
		schema[i] = utils.splitString(schema[i], "|")

		local schema_name = schema[i][1]
		local table_name = schema[i][2]
        if not self.schema[schema_name] then
			self.schema[schema_name] = {
				expanded = false,
				num_tables = 0,
				tables = {},
			}
            self.num_schema = self.num_schema + 1
		end
		if table_name ~= "-" then
			self.schema[schema_name].tables[table_name] = {
				expanded = false,
			}
			self.schema[schema_name].num_tables =
                self.schema[schema_name].num_tables + 1
		end
	end
end


---@param query_type string
---@param query_data table<string>
---The main query execution wrapper.
---Takes 3 types of arguments for `query_type`:
---  - connect
---  - refresh
---  - query
function Connection:executeUv(query_type, query_data)
    local uv = vim.uv

    local stdin = uv.new_pipe()
    local stdout = uv.new_pipe()
    local stderr = uv.new_pipe()

    local handle, _ = uv.spawn("psql", {
        args = {self.url},
        stdio = {stdin, stdout, stderr}
    })

    local stdout_results = {}
    uv.read_start(stdout, vim.schedule_wrap(function(err, data)
        assert(not err, err)
        local ui = require("sqlua.ui")
        if data then
            table.insert(stdout_results, data)
        else
            local final = cleanData(table.concat(stdout_results, ""))
            if next(final) ~= nil then
                if query_type == "connect" then
                    self:getPostgresSchema(final)
                    ui:addConnection(self)
                    ui:refreshSidebar()
                elseif query_type == "refresh" then
                    self.schema = {}
                    self:getPostgresSchema(final)
                    ui:refreshSidebar()
                elseif query_type == "query" then
                    self:query(final)
                end
            end
        end
    end))

    local stderr_results = nil
    uv.read_start(stderr, vim.schedule_wrap(function(err, data)
        assert(not err, err)
        if data then
            if not stderr_results then
                stderr_results = {}
            end
            table.insert(stderr_results, data)
        else
            if stderr_results then
                local final = cleanData(table.concat(stderr_results, ""))
                if next(final) ~= nil then
                    if query_type ~= "refresh" then
                        self:query(final)
                    end
                end
            end
        end
    end))

    uv.write(stdin, query_data)
    uv.shutdown(stdin, function()
        if handle then
            uv.close(handle)
        end
    end)
end



---@param mode string|nil
---@return nil
---Executes a query based on editor that this command was called from
---Optional `mode` determines what is executed:
---  - 'n' - executes entire buffer
---  - 'v' - executes visual selection
---  - 'V' - executes visual line
---  - '^V' - executes visual block
function Connection:execute(--[[optional mode string]] mode)
    if self.name ~= require("sqlua.ui").active_db then
        return
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
		local esc_key = vim.api.nvim_replace_termcodes(
            "<Esc>", false, true, true
        )
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
        local srow, scol, erow, ecol = 0, 0, 0, 0
        local p1 = vim.fn.getpos(".")
        local p2 = vim.fn.getpos("v")
        if p1 and p2 then
            _, srow, scol, _ = unpack(p1)
            _, erow, ecol, _ = unpack(p2)
        end
		if srow < erow or (srow == erow and scol <= ecol) then
			query = vim.api.nvim_buf_get_text(
                0, srow - 1, scol - 1, erow - 1, ecol, {}
            )
		else
			query = vim.api.nvim_buf_get_text(
                0, erow - 1, ecol - 1, srow - 1, scol, {}
            )
		end
	elseif mode == "\22" then
		-- visual block mode
        local srow, scol, erow, ecol = 0, 0, 0, 0
        local p1 = vim.fn.getpos(".")
        local p2 = vim.fn.getpos("v")
        if p1 and p2 then
            _, srow, scol, _ = unpack(p1)
            _, erow, ecol, _ = unpack(p2)
        end
		local lines = vim.api.nvim_buf_get_lines(
            0, math.min(srow, erow) - 1, math.max(srow, erow), false
        )
		query = {}
		local start = math.min(scol, ecol)
		local _end = math.max(scol, ecol)
		for _, line in ipairs(lines) do
			table.insert(query, string.sub(line, start, _end))
		end
	end

    if query then
        for i, j in ipairs(query) do
            query[i] = query[i]:gsub("[\r\n]", " ")
            query[i] = query[i]:gsub("%s+", " ")
            local cleaned = j:gsub("%s+", "")
            if cleaned:sub(1, 1) == "-" and cleaned:sub(2, 2) == '-' then
                table.remove(query, i)
            else
                query[i] = " "..query[i]
            end
        end
        self:executeUv("query", query)
    end
end

---@param name string
---@return nil
---Initializes the connection to the DB, and inserts into UI.
---Required for any operations on the given db.
Connections.connect = function(name)
	local connections = Connections.read()
	for _, connection in pairs(connections) do
		if connection["name"] == name then
			local con = vim.deepcopy(Connection)
			con.name = name
			con.url = connection["url"]
			con.cmd = "psql " .. connection["url"] .. " -c "
			local Queries = require("sqlua.queries.postgres")
			local query = string.gsub(Queries.SchemaQuery, "\n", " ")
            con:executeUv("connect", query)
		end
	end
end

CONNECTIONS_FILE = utils.concat({
    vim.fn.stdpath("data"),
    "sqlua",
    "connections.json"
})

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
