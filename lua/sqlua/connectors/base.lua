local utils = require("sqlua.utils")

---@class ConnectionInfo
---@field dbms string
---@field user string
---@field password string
---@field host string
---@field port string
---@field database string
---@field args table<string>
local ConnectionInfo = {
    dbms = "",
    user = "",
    password = "",
    host = "",
    port = "",
    database = "",
    args = {}
}

---@class Connection
---@field files_expanded boolean sidebar expansion flag
---@field num_schema integer number of schema in this db
---@field name string locally defined db name
---@field url string full url to connect to the db
---@field cmd string cli program cmd name
---@field cli_args table uv.spawn args
---@field dbms string actual db name according to the url
---@field schema table nested schema design for this db
---@field files table all saved files in the local dir
---The primary object representing a single connection to a dbms by url
local Connection = {
    expanded = false,
    loaded = false,
	files_expanded = false,
	num_schema = 0,
	name = "",
	url = "",
    cmd = "",
	dbms = "",
    connection_info = ConnectionInfo,
    schema_query = "",
    cli_args = {},
	schema = {},
	files = {},
    queries = {}
}

---@return Connection
function Connection:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---@overload fun(name: string, url: string) : self
function Connection:setup(name, url)
    name = name
    url = url
    return self
end

---@overload fun(data: table<string>) : table<string>
function Connection:cleanSchema(data)
    return data
end

---@overload fun(table, string) : table
--- dbms specific cleaning
function Connection:dbmsCleanResults(data, query_type)
    return data
end

---@overload fun(data: string) : table
---@param data string
---@return table
--- Takes string results and transforms them to a table of strings
function Connection:baseCleanResults(data)
    local result = {}
    local i = 1
    for c in data:gmatch(string.format("([^%s]+)", '\n')) do
        result[i] = c
        i = i + 1
    end
    return result
end


---@class Database
---@field dbms string
---@field databases table
---@field num_databases integer
---@field expanded boolean
Connection.Database = {
    dbms = "",
    schema = {},
    expanded = false,
}

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
Connection.Schema = {
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
Connection.Query = {
    statement = "",
    results = {}
}

---@returns ConnectionInfo
--- Takes a url and returns a ConnectionInfo object
--- representing connection attributes
function Connection:parseUrl()
    local split = utils.splitString(self.url, ":/@")
    local con_info = vim.deepcopy(ConnectionInfo)
    con_info.dbms = split[1]
    if self.url:find("@") then
        if #split == 3 then
            -- dbms://user@host
            con_info.user = split[2]
            con_info.host = split[3]
        elseif #split == 4 then
            if tonumber(split[4]) then
                -- dbms://user@host:port
                con_info.user = split[2]
                con_info.host = split[3]
                con_info.port = split[4]
            elseif split[4]:find("?") then
                -- dbms://user@host/db?query
                con_info.user = split[2]
                con_info.host = split[3]
                con_info.database = split[4]
            else
                -- dbms://user:pass@host
                con_info.user = split[2]
                con_info.password = split[3]
                con_info.host = split[4]
            end
        elseif #split == 5 then
            if tonumber(split[5]) then
                -- dbms://user:pass@host:port
                con_info.user = split[2]
                con_info.password = split[3]
                con_info.host = split[4]
                con_info.port = split[5]
            else
                -- dbms://user:pass@host?db?query
                con_info.user = split[2]
                con_info.password = split[3]
                con_info.host = split[4]
                con_info.database = split[5]
            end
        else
            -- dbms://user:pass@host:port/db?query
            con_info.user = split[2]
            con_info.password = split[3]
            con_info.host = split[4]
            con_info.port = split[5]
            con_info.database = split[6]
        end
    else
        if #split == 2 then
            -- dbms://host
            con_info.host = split[2]
        elseif #split == 3 then
            if tonumber(split[3]) then
                -- dbms://host:port
                con_info.host = split[2]
                con_info.port = split[3]
            else
                -- dbms://host:db?query
                con_info.host = split[2]
                con_info.database = split[3]
            end
        elseif #split == 4 then
            -- dbms://host:port/db?query
            con_info.host = split[2]
            con_info.port = split[3]
            con_info.database = split[4]
        end
    end
    -- extract query con_info from db name
    if con_info.database ~= "" then
        local args = utils.splitString(con_info.database, '?&')
        con_info.database = args[1]
        table.remove(args, 1)
        for _, item in pairs(args) do
            local user_args = item:match("user=(%w+)")
            local password_args = item:match("password=([%w!-$'-~]+)")
            if user_args then
                con_info.user = user_args
            elseif password_args then
                con_info.password = password_args
            else
                table.insert(con_info.args, item)
            end
        end
    end
    return con_info
end

---@param data table
---@param db? string
---@return nil
--- Populates the Connection's schema based on the stdout
--- from executing the DBMS' SchemaQuery
function Connection:getSchema(data, db)
    local schema = self:cleanSchema(data)
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
            self.schema[s] = vim.deepcopy(Connection.Schema)
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
            local old_s, new_s = old_schema[s], self.schema[s]
            if old_s and not new_s then
                self.schema[s] = st
            elseif new_s and not old_s then
                old_schema[s] = st
            end
            self.schema[s].expanded = old_schema[s].expanded
            local types = { "tables", "views", "functions", "procedures" }
            for _, type in pairs(types) do
                for i, tbl in pairs(self.schema[s][type]) do
                    local old = old_schema[s][type][i]
                    local new = self.schema[s][type][i]
                    if old and not new then
                        self.schema[s][type][i] = tbl
                    elseif new and not old then
                        old_schema[s][type][i] = tbl
                    end
                    self.schema[s][type][i].expanded =
                        old_schema[s][type][i].expanded
                end
                self.schema[s][type.."_expanded"] =
                    old_schema[s][type.."_expanded"]
            end
        end
    end
end


---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val)
	vim.api.nvim_set_option_value("modifiable", val, { buf = buf })
end


---@param buf buffer
---@param val boolean
---@return nil
Connection.setSidebarModifiable = function(buf, val)
	vim.api.nvim_set_option_value("modifiable", val, { buf = buf })
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

    local q = vim.deepcopy(Connection.Query)
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

---@param query_type string
---@param query_data string|table<string>
---@param db string|nil
---The main query execution wrapper.
---Takes 3 types of arguments for `query_type`:
---  - connect
---  - refresh
---  - query
function Connection:executeUv(query_type, query_data, --[[optional]] db)
    -- TODO: comments in code need to have space added
    if #query_data == 1 and query_data[1] == " " then
        return
    end

    if type(query_data) ~= 'table' then
        query_data = {query_data}
    end

    local uv = vim.uv

    local stdin = uv.new_pipe()
    local stdout = uv.new_pipe()
    local stderr = uv.new_pipe()

    local handle, _ = uv.spawn(self.cmd, {
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
            local base = self:baseCleanResults(table.concat(results, ""))
            local final = self:dbmsCleanResults(base, query_type)
            if next(final) ~= nil then
                if query_type == "connect" then
                    self:getSchema(final)
                    ui:addConnection(self)
                elseif query_type == "refresh" then
                    self:getSchema(final, db)
                elseif query_type == "query" then
                    self:query(query_data, final)
                    vim.api.nvim_win_close(ui.windows.query_float, true)
                    ui.windows.query_float = nil
                    if ui.options.syntax_highlighting == true then
                        ui.highlightResultsPane()
                    end
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

function Connection:connect()
    self:executeUv("connect", self.schema_query)
    self.loaded = true
end

return Connection
