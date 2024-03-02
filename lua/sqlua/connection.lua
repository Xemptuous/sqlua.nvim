local utils = require("sqlua.utils")

---@class Connections
local Connections = {}

---@class Schema
---@field dbms string
---@field tables table
---@field views table
---@field functions table
---@field procedures table
---@field num_tables integer
---@field num_views integer
---@field num_functions integer
---@field num_procedures integer
---@field expanded boolean
---@field tables_expanded boolean
---@field views_expanded boolean
---@field functions_expanded boolean
---@field procedures_expanded boolean
local Schema = {
    dbms = "",
    tables = {},
    views = {},
    functions = {},
    procedures = {},
    num_tables = 0,
    num_views = 0,
    num_functions = 0,
    num_procedures = 0,
    expanded = false,
    tables_expanded = false,
    views_expanded = false,
    functions_expanded = false,
    procedures_expanded = false,
}

---@class Query
---@field statement string|table
---@field results table
local Query = {
    statement = "",
    results = {}
}

---@class Connection
---@field files_expanded boolean sidebar expansion flag
---@field num_schema integer number of schema in this db
---@field name string locally defined db name
---@field url string full url to connect to the db
---@field cmd string query to execute
---@field cli string cli program cmd name
---@field cli_args table uv.spawn args
---@field dbms string actual db name according to the url
---@field schema table nested schema design for this db
---@field files table all saved files in the local dir
---The primary object representing a single connection to a dbms by url
local Connection = {
    expanded = false,
	files_expanded = false,
	num_schema = 0,
	name = "",
	url = "",
	cmd = "",
    cli = "",
	dbms = "",
    cli_args = {},
	schema = {},
	files = {},
    queries = {}
}


---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val)
	vim.api.nvim_set_option_value("modifiable", val, { buf = buf })
end


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
function Connection:query(query, data)
	local win = vim.api.nvim_get_current_win()
	local pos = vim.api.nvim_win_get_cursor(win)
	local buf = vim.api.nvim_win_get_buf(win)
    if data[1] == "" then
        return
    end

    local q = vim.deepcopy(Query)
    q.statement = query
    q.results = data
    table.insert(self.queries, q)

    local ui = require("sqlua.ui")
    if ui.buffers.results ~= nil then
        setSidebarModifiable(ui.buffers.results, true)
        vim.api.nvim_buf_set_lines(ui.buffers.results, 0, -1, false, data)
        vim.api.nvim_win_set_cursor(ui.windows.results, {1, 0})
        setSidebarModifiable(ui.buffers.results, false)
    else
        ui:createResultsPane(data)
        vim.api.nvim_win_set_cursor(ui.windows.results, {1, 0})
    end
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_cursor(win, pos)
end

---@param data table
---@return nil
--- Populates the Connection's schema based on the stdout
--- from executing the DBMS' SchemaQuery
function Connection:getSchema(data)
	local schema = utils.shallowcopy(data)
    if self.dbms == "postgresql" then
        table.remove(schema, 1)
        table.remove(schema, 1)
        table.remove(schema)
        for i, _ in ipairs(schema) do
            schema[i] = string.gsub(schema[i], "%s", "")
            schema[i] = utils.splitString(schema[i], "|")
        end
    elseif self.dbms == "mysql" or self.dbms == "mariadb" then
        table.remove(schema, 1)
        table.remove(schema, 1)
        table.remove(schema, 1)
        table.remove(schema)
        for i, _ in ipairs(schema) do
            schema[i] = string.gsub(schema[i], "%s", "")
            schema[i] = string.sub(schema[i], 2, -2)
            schema[i] = utils.splitString(schema[i], "|")
        end
    end

    local old_schema = nil
    if next(self.schema) ~= nil then
        old_schema = vim.deepcopy(self.schema)
    end
    self.num_schema = 0
    self.schema = {}

	for i, _ in ipairs(schema) do
        local type = schema[i][1]
		local s = schema[i][2] -- schema
		local t = schema[i][3] -- table/view/proc/func
        if not self.schema[s] then
            self.schema[s] = vim.deepcopy(Schema)
            self.num_schema = self.num_schema + 1
            self.schema[s].dbms = self.dbms
		end
		if t ~= "-" then
            if type == "function" then
                self.schema[s].functions[t] = { expanded = false }
                self.schema[s].num_functions =
                    self.schema[s].num_functions + 1
            elseif type == "table" then
                self.schema[s].tables[t] = { expanded = false }
                self.schema[s].num_tables =
                    self.schema[s].num_tables + 1
            elseif type == "view" then
                self.schema[s].views[t] = { expanded = false }
                self.schema[s].num_views =
                    self.schema[s].num_views + 1
            else
                self.schema[s].procedures[t] = { expanded = false }
                self.schema[s].num_procedures =
                    self.schema[s].num_procedures + 1
            end
		end
	end
    if old_schema ~= nil then
        for s, st in pairs(self.schema) do
            local os, ns = old_schema[s], self.schema[s]
            if os ~= nil and ns == nil then
                self.schema[s] = st
            elseif os == nil and ns ~= nil then
                old_schema[s] = st
            end
            self.schema[s].expanded = old_schema[s].expanded
            if next(self.schema) ~= nil then
                for t, tt in pairs(self.schema[s]) do
                    local ost, nst = old_schema[s][t], self.schema[s][t]
                    if ost ~= nil and nst == nil then
                        self.schema[s][t] = tt
                    elseif ost == nil and nst ~= nil then
                        old_schema[s][t] = tt
                    end
                end
            end
        end
    end
end


---@param query_type string
---@param query_data string|table<string>
---The main query execution wrapper.
---Takes 3 types of arguments for `query_type`:
---  - connect
---  - refresh
---  - query
function Connection:executeUv(query_type, query_data)
    -- TODO: comments in code need to have space added
    if #query_data == 1 and query_data[1] == " " then
        return
    end
    local uv = vim.uv

    local stdin = uv.new_pipe()
    local stdout = uv.new_pipe()
    local stderr = uv.new_pipe()

    local handle, _ = uv.spawn(self.cli, {
        args = self.cli_args,
        stdio = {stdin, stdout, stderr}
    })

    local results = {}
    local ui = require("sqlua.ui")
    uv.read_start(stdout, vim.schedule_wrap(function(err, data)
        assert(not err, err)
        if data then
            table.insert(results, data)
        else
            local final = cleanData(table.concat(results, ""))
            if self.dbms == "mysql" then
                if string.find(final[1], "mysql%: %[Warning%]") then
                    table.remove(final, 1)
                end
            end
            if next(final) ~= nil then
                if query_type == "connect" then
                    self:getSchema(final)
                    ui:addConnection(self)
                elseif query_type == "refresh" then
                    self:getSchema(final)
                elseif query_type == "query" then
                    self:query(query_data, final)
                    vim.api.nvim_win_close(ui.windows.query_float, true)
                    ui.windows.query_float = nil
                end
                ui:refreshSidebar()
            else
                if ui.windows.query_float then
                    vim.api.nvim_win_close(ui.windows.query_float, true)
                    ui.windows.query_float = nil
                end
            end
        end
    end))


    uv.read_start(stderr, vim.schedule_wrap(function(err, data)
        assert(not err, err)
        if data then
            table.insert(results, data)
        end
    end))

    uv.write(stdin, query_data, function()
    end)


    uv.shutdown(stdin, vim.schedule_wrap(function()
        if query_type == "query" then
            setSidebarModifiable(ui.buffers.results, true)
            if ui.buffers.results ~= nil then
                vim.api.nvim_buf_set_lines(
                    ui.buffers.results, 0, -1, false, {})
            else
                ui:createResultsPane({})
            end
            if not ui.windows.query_float then
                local w = vim.api.nvim_win_get_width(ui.windows.results)
                local h = vim.api.nvim_win_get_height(ui.windows.results)
                local b = vim.api.nvim_create_buf(false, true)
                ui.buffers.query_float = b
                local fwin = vim.api.nvim_open_win(b, false, {
                    relative='win',
                    win=ui.windows.results,
                    row=h/2 - 1,
                    col=w/2 - math.floor(w/3) / 2,
                    width=math.floor(w/3), height=1,
                    border="single", title="Querying", title_pos="center",
                    style="minimal",
                    focusable=false,
                })
                ui.windows.query_float = fwin
                local sep = string.rep(" ",
                    math.floor(w / 3 / 2) -
                        math.ceil(string.len("Executing Query") / 2))
                vim.api.nvim_buf_set_lines(b, 0, -1, false, {
                    sep.."Executing Query"
                })
            end
            setSidebarModifiable(ui.buffers.results, false)
            uv.close(handle)
        end
    end))
    -- TODO: implement async "time elapsed" for query.
    -- below was an attempt, but can't use vim.api or globals
    -- inside of uv.new_thread()

    -- local start_time = os.clock() * 100
    -- local query_thread
    -- query_thread = uv.new_thread(function(...)
    --     local se, so, stime, rbuf = ...
    --     print(se, so)
    --     print("//////////// LOOP START")
    --     while(se:is_active()) do
    --         -- vim.api.nvim_buf_set_lines(
    --         --     rbuf, 0, -1, false, {
    --         --         "Fetching ",
    --         --         tostring(stime - os.clock() * 100)
    --         -- })
    --     end
    --     print("//////////// LOOP DONE")
    -- end, stdout, stderr, start_time, ui.buffers.results)
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

    local final_query = {}
    if query then
        for i, j in ipairs(query) do
            query[i] = j:gsub("[\r\n]", " ")
            query[i] = " "..query[i]:match("^%s*(.-)%s*$").." "
            local cleaned = j:match("^%s*(.-)%s*$")
            if cleaned:match("^%-%-") or cleaned:match("^%#") then
            else
                table.insert(final_query, query[i])
            end
        end
        self:executeUv("query", final_query)
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

            local parsed = utils.parseUrl(connection["url"])
            con.dbms = parsed.dbms
            con.url = connection["url"]

            if parsed.dbms == "postgresql" then
                con.cli = "psql"
                con.cmd = "psql "..connection["url"].." -c "
                con.cli_args = {con.url}
            elseif parsed.dbms == "mysql" then
                con.cli = "mysql"
                con.cli_args = utils.getCLIArgs("mysql", parsed)
            elseif parsed.dbms == "mariadb" then
                con.cli = "mariadb"
                con.cli_args = utils.getCLIArgs("mysql", parsed)
            end
            local queries = require("sqlua.queries."..con.dbms).SchemaQuery
            local query = string.gsub(queries, "\n", " ")
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
