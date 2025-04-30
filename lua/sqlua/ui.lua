---@alias namespace_id integer
---@alias iterator function
---@alias buffer integer
---@alias window integer

---@class Buffers
---@field sidebar integer|nil
---@field results integer|nil
---@field query_float integer|nil
---@field editors table
local Buffers = {
    sidebar = nil,
    results = nil,
    query_float = nil,
    editors = {},
}
---@class Windows
---@field sidebar integer|nil
---@field results integer|nil
---@field query_float integer|nil
---@field editors table
local Windows = {
    sidebar = nil,
    results = nil,
    query_float = nil,
    editors = {},
}

--- Primary wrapper for the entire UI
---@class UI
---@field initial_layout_loaded boolean
---@field help_toggled boolean
---@field help_length integer number if lines/items in the "toggle help" area
---@field sidebar_ns namespace_id
---@field active_db string
---@field dbs table
---@field num_dbs integer
---@field buffers Buffers
---@field windows Windows
---@field last_cursor_position table
---@field last_active_buffer buffer
---@field current_active_buffer buffer
---@field last_active_window window
---@field current_active_window window
---@field queries table previous query results
---@field results_expanded boolean
local UI = {
    initial_layout_loaded = false,
    help_toggled = false,
    help_length = 0,
    sidebar_ns = 0,
    buffers_expanded = false,
    active_db = "",
    dbs = {},
    num_dbs = 0,
    buffers = Buffers,
    windows = Windows,
    last_cursor_position = {
        sidebar = {},
        editor = {},
        result = {},
    },
    last_active_buffer = 0,
    current_active_buffer = 0,
    last_active_window = 0,
    current_active_window = 0,
    queries = {},
    results_expanded = false,
}

local Utils = require("sqlua.utils")

local UI_ICONS = {
    expanded = "",
    collapsed = "",
    db = "",
    db2 = "",
    buffers = "",
    folder = "",
    schema = "󱏒",
    views = "󱇜",
    view = "",
    functions = "󰡱",
    _function = "󰊕",
    procedures = "󰯃",
    procedure = "󰯂",
    tables = "󰾇",
    table = "",
    file = "",
    results = "",
    dbout = "󰦨",
    new_query = "",
    table_stmt = "",
}
--- Create a string of all icons for substitution purposes
UI_ICONS.icons_sub = function()
    local final = {}
    for _, icon in pairs(UI_ICONS) do
        if type(icon) == "string" then table.insert(final, icon) end
    end
    return table.concat(final, "")
end
local ICONS_SUB_STRING = UI_ICONS.icons_sub()
local ICONS_SUB_REGEX = "[" .. ICONS_SUB_STRING .. "]"
local EDITOR_NUM = 1

---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val) vim.api.nvim_set_option_value("modifiable", val, { buf = buf }) end

---Adds the Connection object to the UI object
---@param con Connection
function UI:addConnection(con)
    local db = con.name
    if UI.active_db == "" then UI.active_db = db end
    UI.dbs[db] = con
    local files = vim.deepcopy(require("sqlua.files"))
    UI.dbs[db].files = files:setup(db)
    UI.num_dbs = UI.num_dbs + 1
    setSidebarModifiable(UI.buffers.sidebar, false)
end

---Sets highlighting in the sidebar based on the hl
---@return nil
local function highlightSidebarNumbers()
    local buf = vim.api.nvim_win_get_buf(UI.windows.sidebar)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, vim.api.nvim_buf_line_count(buf), false)
    for line, text in ipairs(lines) do
        -- add highlight excluding final "count" in parens
        local s = text:find("%s%(")
        local e = text:find("%)$")
        if s and e then vim.api.nvim_buf_add_highlight(UI.buffers.sidebar, UI.sidebar_ns, "Comment", line - 1, s, e) end
    end
end

---Searches existing buffers and returns the buffer type, and buffer number
---@param buf buffer
---@return string|nil, buffer|nil
local function getBufferType(buf)
    if UI.buffers.sidebar == buf then
        return "sidebar", UI.buffers.sidebar
    elseif UI.buffers.results == buf then
        return "result", buf
    end
    for _, v in pairs(UI.buffers.editors) do
        if v == buf then return "editor", v end
    end
end

--[[Recursively searches the given table to toggle the 'expanded'
  attribute for the given item.
]]
---@param table table table to begin the search at
---@param search string what to search for to toggle
---@return nil
local function toggleExpanded(table, search)
    for key, value in Utils.pairsByKeys(table) do
        if key == search then
            table[search].expanded = not table[search].expanded
            return
        elseif type(value) == "table" then
            toggleExpanded(value, search)
        end
    end
end

---@param buf buffer sidebar buffer
---@param srow integer starting row to indent
---@param sep string length of whitespace indent
---@param text string text to print
---@return integer
local function printSidebarExpanded(buf, srow, sep, text)
    vim.api.nvim_buf_set_lines(buf, srow, srow, false, {
        sep .. UI_ICONS.expanded .. " " .. text,
    })
    return srow + 1
end

---@param buf buffer sidebar buffer
---@param srow integer starting row to indent
---@param sep string length of whitespace indent
---@param text string text to print
---@return integer
local function printSidebarCollapsed(buf, srow, sep, text)
    vim.api.nvim_buf_set_lines(buf, srow, srow, false, {
        sep .. UI_ICONS.collapsed .. " " .. text,
    })
    return srow + 1
end

---@param buf buffer sidebar buffer
---@param srow integer starting row to indent
---@param text string text to print
---@return integer
local function printSidebarEmpty(buf, srow, text)
    vim.api.nvim_buf_set_lines(buf, srow, srow, false, { text })
    return srow + 1
end

---@param win window
---@return buffer
local function createEditor(win)
    local name = Utils.concat({
        vim.fn.stdpath("data"),
        "sqlua",
        "Editor_" .. EDITOR_NUM .. ".sql",
    })
    vim.api.nvim_set_current_win(win)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, name)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.cmd("setfiletype sql")
    table.insert(UI.buffers.editors, buf)
    if not UI.last_active_window or not UI.last_active_buffer then
        UI.last_active_buffer = buf
        UI.last_active_window = win
    end
    EDITOR_NUM = EDITOR_NUM + 1
    return buf
end

---Recreates the editor window when no editor windows exist
local function recreateEditor()
    local sidebar_win = vim.api.nvim_get_current_win()
    UI.windows.sidebar = sidebar_win
    vim.cmd("vsplit")
    local editor_win = vim.api.nvim_get_current_win()
    table.insert(UI.windows.editors, editor_win)

    createEditor(editor_win)
    vim.api.nvim_win_set_width(UI.windows.sidebar, 40)
end

---Creates the specified statement to query the given table.
---Query is pulled based on active_db dbms, and fills the available buffer.
---@param type string the type of table statement
---@param tbl string table
---@param schema string schema
---@param db string database
---@return nil
local function createTableStatement(type, tbl, schema, database, db, dbms)
    local queries = require("sqlua.queries." .. dbms)
    local win = nil
    local buf = nil
    type = type:gsub("%s+", "")
    for _, w in pairs(UI.windows.editors) do
        for _, b in pairs(UI.buffers.editors) do
            local name = vim.api.nvim_buf_get_name(b)
            if name:match("Editor_%d.sql") then
                win = w
                buf = b
                break
            end
        end
    end
    if not win or not buf then
        createEditor(UI.windows.editors[1])
        return
    end
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    local stmt = {}
    local query = queries[type]({
        table = tbl,
        schema = schema,
        db = db,
        limit = UI.options.default_limit,
    })
    for line in string.gmatch(query, "[^\r\n]+") do
        table.insert(stmt, line)
    end
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, stmt)
    UI.dbs[database]:execute()
end

---returns a numeric count of indent level based on leading whitespace
---@param val string
---@return number
local function countIndentWhitespace(val)
    local current_indent = 0
    for i = 1, #val do
        local c = val:sub(i, i)
        if c:match("[A-Za-z0-9_]") then
            current_indent = i - 9
            break
        end
    end
    return current_indent
end

--[[Searches the sidebar from the given starting point upwards
  for the given type, returning the first occurence of either
  table, schema, or db
]]
local sidebarFind = {
    ---@param num integer sidebar starting line
    table = function(num)
        local tbl = nil
        while true do
            tbl = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if not tbl then
                return
            elseif string.find(tbl, UI_ICONS.table) then
                break
            end
            num = num - 1
        end
        num = num - 1
        if tbl then
            if tbl:find("%(") then tbl = tbl:sub(1, tbl:find("%(") - 1) end
        end
        return tbl, num
    end,
    ---@param num integer sidebar starting line
    database = function(num)
        local db = nil
        while true do
            db = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if not db then return nil end
            if string.find(db, UI_ICONS.db) then
                db = db:gsub("%(%d*%)", "")
                db = db:gsub("%s+[^%w]+", "")
                db = db:gsub(ICONS_SUB_REGEX, "")
                -- trim
                db = db:gsub("^%s*(.-)%s*$", "%1")
                break
            end
            num = num - 1
        end
        if db then
            if db:find("%(") then db = db:sub(1, db:find("%(") - 1) end
        end
        return db, num
    end,
    ---@param num integer sidebar starting line
    schema = function(num)
        local schema = nil
        while true do
            schema = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if schema == nil then break end
            if string.find(schema, UI_ICONS.schema) then break end
            num = num - 1
        end
        if schema then
            if schema:find("%(") then schema = schema:sub(1, schema:find("%(") - 1) end
        end
        return schema, num
    end,
    ---@param num integer sidebar starting line
    snowflake_db = function(num)
        local db = nil
        while true do
            db = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if string.find(db, UI_ICONS.db2) then
                db = db:gsub("%s+[^%w]+", "")
                db = db:gsub(ICONS_SUB_REGEX, "")
                break
            end
            num = num - 1
        end
        if db then
            if db:find("%(") then db = db:sub(1, db:find("%(") - 1) end
        end
        return db, num
    end,
    ---@param num integer sidebar starting line
    first_collapsible = function(num)
        local line = nil
        while true do
            line = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if not line then
                return
            elseif string.find(line, UI_ICONS.expanded) or string.find(line, UI_ICONS.collapsed) then
                break
            end
            num = num - 1
        end
        num = num - 1
        if line then
            if line:find("%(") then line = line:sub(1, line:find("%(") - 1) end
        end
        return line, num
    end,
    ---@param num integer sidebar starting line
    first_parent = function(num)
        local line = nil
        local initial_indent = nil
        while true do
            line = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, false)[1]
            if not line then return end
            if initial_indent == nil then
                initial_indent = countIndentWhitespace(line)
            elseif countIndentWhitespace(line) < initial_indent then
                break
            end
            num = num - 1
        end
        num = num - 1
        if line then
            if line:find("%(") then line = line:sub(1, line:find("%(") - 1) end
        end
        return line, num
    end,
}

---The primary way of refreshing the sidebar to account for any changes
function UI:refreshSidebar()
    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param schema Schema schema name
    ---@return integer srow
    local function refreshTables(buf, srow, sep, schema)
        local queries = require("sqlua/queries." .. schema.dbms)
        local statements = queries.ddl

        local nt = schema.num_tables or 0
        local text = UI_ICONS.tables .. " Tables (" .. nt .. ")"

        if not schema.tables_expanded then return printSidebarCollapsed(buf, srow, sep, text) end

        srow = printSidebarExpanded(buf, srow, sep, text)
        for table, _ in Utils.pairsByKeys(schema.tables) do
            local txt = UI_ICONS.table .. " " .. table

            if not schema.tables[table].expanded then
                srow = printSidebarCollapsed(buf, srow, sep .. "  ", txt)
            else
                srow = printSidebarExpanded(buf, srow, sep .. "  ", txt)
                for _, stmt in Utils.pairsByKeys(statements) do
                    txt = UI_ICONS.table_stmt .. " " .. stmt
                    srow = printSidebarEmpty(buf, srow, sep .. "      " .. txt)
                end
            end
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param schema Schema schema name
    ---@return integer srow
    local function refreshViews(buf, srow, sep, schema)
        local nv = schema.num_views or 0
        local v_text = UI_ICONS.views .. " Views (" .. nv .. ")"

        if not schema.views_expanded then return printSidebarCollapsed(buf, srow, sep, v_text) end

        srow = printSidebarExpanded(buf, srow, sep, v_text)
        for view, _ in Utils.pairsByKeys(schema.views) do
            local text = UI_ICONS.view .. " " .. view
            srow = printSidebarEmpty(buf, srow, sep .. "    " .. text)
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param schema Schema schema name
    ---@param sep string length of whitespace indent
    ---@return integer srow
    local function refreshFunctions(buf, srow, sep, schema)
        local nf = schema.num_functions or 0
        local f_text = UI_ICONS.functions .. " Functions (" .. nf .. ")"

        if not schema.functions_expanded then return printSidebarCollapsed(buf, srow, sep, f_text) end

        srow = printSidebarExpanded(buf, srow, sep, f_text)
        for fn, _ in Utils.pairsByKeys(schema.functions) do
            local text = UI_ICONS._function .. " " .. fn
            srow = printSidebarEmpty(buf, srow, sep .. "    " .. text)
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param schema Schema schema name
    ---@return integer srow
    local function refreshProcedures(buf, srow, sep, schema)
        local ns = schema.num_procedures or 0
        local p_text = UI_ICONS.procedures .. " Procedures (" .. ns .. ")"

        if not schema.procedures_expanded then return printSidebarCollapsed(buf, srow, sep, p_text) end

        srow = printSidebarExpanded(buf, srow, sep, p_text)
        for fn, _ in Utils.pairsByKeys(schema.procedures) do
            local text = UI_ICONS.procedure .. " " .. fn
            srow = printSidebarEmpty(buf, srow, sep .. "    " .. text)
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param file table file name
    ---@return integer srow
    local function refreshSavedQueries(buf, srow, sep, file)
        if not file.isdir then
            local text = UI_ICONS.file .. " " .. file.name
            return printSidebarEmpty(buf, srow, sep .. "  " .. text)
        end

        local text = UI_ICONS.folder .. " " .. file.name

        if not file.expanded then return printSidebarCollapsed(buf, srow, sep, text) end

        srow = printSidebarExpanded(buf, srow, sep, text)
        if next(file.files) ~= nil then
            for _, f in Utils.pairsByKeys(file.files) do
                srow = refreshSavedQueries(buf, srow, sep .. "  ", f)
            end
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param db string db name
    ---@return integer srow
    local function refreshSchema(buf, srow, sep, db)
        local s = self.dbs[db].schema
        for schema, _ in Utils.pairsByKeys(s) do
            local text = UI_ICONS.schema .. " " .. schema
            if type(s[schema]) == "table" then
                if not s[schema].expanded then
                    srow = printSidebarCollapsed(buf, srow, sep, text)
                else
                    srow = printSidebarExpanded(buf, srow, sep, text)
                    local ns = sep .. "  "
                    srow = refreshTables(buf, srow, ns, s[schema])
                    srow = refreshViews(buf, srow, ns, s[schema])
                    srow = refreshFunctions(buf, srow, ns, s[schema])
                    srow = refreshProcedures(buf, srow, ns, s[schema])
                end
            end
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param sep string length of whitespace indent
    ---@param db string db name
    ---@return integer srow
    local function refreshSnowflakeDatabases(buf, srow, sep, db)
        local s = self.dbs[db].schema
        if not s.databases_loaded then srow = printSidebarEmpty(buf, srow, sep .. "  󰑐 Loading Databases...") end
        for sfdb, _ in Utils.pairsByKeys(s) do
            local text = UI_ICONS.db2 .. " " .. sfdb
            if type(s[sfdb]) == "table" then
                if not s[sfdb].expanded then
                    srow = printSidebarCollapsed(buf, srow, sep, text)
                else
                    srow = printSidebarExpanded(buf, srow, sep, text)
                    local sep2 = sep .. "  "
                    local sf = self.dbs[db].schema[sfdb]
                    for schema, _ in Utils.pairsByKeys(sf.schema) do
                        local text2 = UI_ICONS.schema .. " " .. schema
                        if type(sf.schema[schema]) == "table" then
                            if not sf.schema[schema].expanded then
                                srow = printSidebarCollapsed(buf, srow, sep2, text2)
                            else
                                srow = printSidebarExpanded(buf, srow, sep2, text2)
                                local ns = sep2 .. "  "
                                srow = refreshTables(buf, srow, ns, sf.schema[schema])
                                srow = refreshViews(buf, srow, ns, sf.schema[schema])
                                if not sf.schema[schema].functions_loaded then
                                    srow = printSidebarEmpty(buf, srow, sep .. "  󰑐 Loading Functions & Procedures")
                                end
                                srow = refreshFunctions(buf, srow, ns, sf.schema[schema])
                                srow = refreshProcedures(buf, srow, ns, sf.schema[schema])
                            end
                        end
                    end
                end
            end
        end
        return srow
    end

    ---@param buf buffer sidebar buffer
    ---@param srow integer starting row to indent
    ---@param db string db name
    local function refreshDatabase(buf, srow, db)
        local sep = "   "

        local queries_text = UI_ICONS.folder .. " " .. "Queries"
        if not self.dbs[db].files_expanded then
            srow = printSidebarCollapsed(buf, srow, sep, queries_text)
        else
            srow = printSidebarExpanded(buf, srow, sep, queries_text)
            for _, file in Utils.pairsByKeys(self.dbs[db].files.files) do
                srow = refreshSavedQueries(buf, srow, sep .. "  ", file)
            end
        end

        if db == "snowflake" then return refreshSnowflakeDatabases(buf, srow, sep, db) end
        return refreshSchema(buf, srow, sep, db)
    end

    -- primary start of UI:refreshSidebar
    local sep = " "
    local setCursor = self.last_cursor_position.sidebar
    local winPos = vim.fn.winsaveview()
    local srow = 2 -- starting row pos in sidebar
    local buf = self.buffers.sidebar

    if buf == nil then return end

    -- "Help" section for both expanded and collapsed
    local winwidth = vim.api.nvim_win_get_width(self.windows.sidebar)
    local helptext = "press ? to toggle help"
    local hl = string.len(helptext) / 2
    local helpTextTable = {
        string.format("%+" .. winwidth / 2 - hl .. "s%s", "", helptext),
        " a - add a file in the select dir",
        " d - delete the select file",
        " o - fold the current node",
        " O - fold to first collapsible parent",
        " " .. self.options.keybinds.activate_db .. " - set the active db",
        " <leader>st - toggle sidebar",
        " <leader>sf - focus sidebar",
        " " .. self.options.keybinds.execute_query .. " - run query",
    }
    UI.help_length = #helpTextTable + 2

    setSidebarModifiable(buf, true)
    vim.api.nvim_buf_set_lines(self.buffers.sidebar, 0, -1, false, {})

    if self.help_toggled then
        vim.cmd("syn match SQLuaHelpKey /.*\\( -\\)\\@=/")
        vim.cmd("syn match SQLuaHelpText /\\(- \\).*/")
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, helpTextTable)
        vim.cmd("syn match SQLuaHelpText /^$/")
        srow = srow + #helpTextTable - 1
        vim.api.nvim_buf_add_highlight(self.buffers.sidebar, self.sidebar_ns, "Comment", 0, 0, winwidth)
        setCursor[1] = setCursor[1] + #helpTextTable
    else
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
            string.format("%+" .. winwidth / 2 - hl .. "s%s", "", helptext),
        })
        vim.api.nvim_buf_add_highlight(self.buffers.sidebar, self.sidebar_ns, "Comment", 0, 0, winwidth)
    end

    --- Setup "New Editor" section
    local new_query_text = UI_ICONS.new_query .. " " .. "New Editor"
    printSidebarEmpty(buf, srow - 1, sep .. new_query_text)

    -- Setup "Buffers" section
    local buffers_text = UI_ICONS.buffers .. " " .. "Buffers"
    buffers_text = buffers_text .. " (" .. #self.buffers.editors .. ")"
    if not self.buffers_expanded then
        srow = printSidebarCollapsed(buf, srow, sep, buffers_text)
    else
        srow = printSidebarExpanded(buf, srow, sep, buffers_text)
        for _, ebuf in Utils.pairsByKeys(self.buffers.editors) do
            local editor_name = vim.api.nvim_buf_get_name(ebuf)
            local split = Utils.splitString(editor_name, Utils.sep)
            local text = sep .. "    " .. UI_ICONS.buffers .. " " .. split[#split]
            srow = printSidebarEmpty(buf, srow, text)
        end
    end
    srow = srow + 1

    -- Setup Databases
    local db_rows = {}
    for db, _ in Utils.pairsByKeys(self.dbs) do
        -- if db items loaded and populated
        if self.dbs[db].loaded then
            local n = 0 -- number of items (db/schema)
            if self.dbs[db].dbms == "snowflake" then
                n = self.dbs[db].num_databases or 0
            else
                n = self.dbs[db].num_schema or 0
            end

            local text = UI_ICONS.db .. " " .. db .. " (" .. n .. ")"
            if self.dbs[db].expanded then
                db_rows[db] = srow - 1
                printSidebarExpanded(buf, srow - 1, sep, text)
                srow = refreshDatabase(buf, srow, db)
            else
                -- no need to recurse and handle db items if not open
                db_rows[db] = srow - 1
                printSidebarCollapsed(buf, srow - 1, sep, text)
            end
        else
            -- not loaded, show loading text
            local text = UI_ICONS.db .. " " .. db
            if self.dbs[db].loading then
                db_rows[db] = srow - 1
                printSidebarExpanded(buf, srow - 1, sep, text)
                srow = printSidebarEmpty(buf, srow, sep .. "  󰑐 Loading ...")
            else
                db_rows[db] = srow - 1
                printSidebarCollapsed(buf, srow - 1, sep, text)
            end
        end
        -- highlight db if is active
        if db == self.active_db then
            local sbuf = UI.buffers.sidebar or 0
            local sr = db_rows[db]
            local txt = vim.api.nvim_buf_get_lines(sbuf, sr, sr + 1, true)[1]
            local start = txt:find(UI_ICONS.db) + 1
            local stop = txt:find("%(") or #db + start + 2
            vim.api.nvim_buf_add_highlight(sbuf, UI.sidebar_ns, "SQLua_active_db", sr, start, stop)
        end
        srow = srow + 1
    end
    srow = srow - 1

    -- Setup "Results" section
    local dbout_text = UI_ICONS.results .. " " .. "Results (" .. #self.queries .. ")"
    if not self.results_expanded then
        srow = printSidebarCollapsed(buf, srow, sep, dbout_text)
    else
        srow = printSidebarExpanded(buf, srow, sep, dbout_text)
        local query_results = {}
        for i, tbl in ipairs(self.queries) do
            local text = sep .. "    " .. UI_ICONS.dbout .. " " .. tostring(i)
            local stmt = table.concat(tbl.statement, "")
            table.insert(query_results, text .. " (" .. stmt .. ")")
        end
        for _, q in ipairs(Utils.reverse(query_results)) do
            srow = printSidebarEmpty(buf, srow, q:gsub("[\n\r\t]", " "))
        end
    end

    --- error bounds checking for cursor entering the sidebar
    if not pcall(function() vim.api.nvim_win_set_cursor(self.windows.sidebar, setCursor) end) then
        local min = math.min(srow, self.last_cursor_position.sidebar[1] - #helpTextTable)
        local max = math.max(2, self.last_cursor_position.sidebar[2])
        if min <= 0 then min = 1 end
        vim.api.nvim_win_set_cursor(self.windows.sidebar, { min, max })
    end

    vim.fn.winrestview(winPos)
    highlightSidebarNumbers()
    setSidebarModifiable(buf, false)
end

--- open selected file in sidebar in first editor
---@param db string
---@param filename string
local function openFileInEditor(db, filename)
    local path = UI.dbs[db].files:find(filename).path
    local real_path = vim.uv.fs_realpath(path)
    local existing_buf = nil
    for _, buffer in pairs(UI.buffers.editors) do
        local name = vim.api.nvim_buf_get_name(buffer)
        if name == real_path then existing_buf = buffer end
    end
    if existing_buf then
        vim.api.nvim_win_set_buf(UI.windows.editors[1], existing_buf)
    else
        local buf = vim.api.nvim_create_buf(true, false)
        table.insert(UI.buffers.editors, buf)
        vim.api.nvim_buf_set_name(buf, path)
        vim.api.nvim_buf_call(buf, vim.cmd.edit)
        vim.api.nvim_win_set_buf(UI.windows.editors[1], buf)
    end
end

---Takes query output and creates a 'Results' window & buffer
---@param data table
---@return integer, integer result win and buf
function UI:createResultsPane(data)
    vim.cmd("split")
    local win = vim.api.nvim_get_current_win()
    local buf = nil

    if Utils.getBufferByName("ResultsBuf") == nil then
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, "ResultsBuf")
    else
        buf = existing_buf
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    end

    self.buffers.results = buf
    self.windows.results = win
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, data)
    vim.cmd(":wincmd J")
    vim.api.nvim_win_set_height(0, 10)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("wrap", false, { win = win })
    vim.api.nvim_set_option_value("number", false, { win = win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = win })
    vim.cmd("goto 1")
    vim.api.nvim_set_current_buf(self.last_active_buffer)
    return win, buf
end

--- helper to get cleaned (db, schema) without icons given current cursor position
---@param cursorPos integer row position
---@return string|nil, string|nil
local function getDatabaseAndSchema(cursorPos)
    local db, _ = sidebarFind.database(cursorPos)
    local _, schema = pcall(function()
        local s = sidebarFind.schema(cursorPos)
        if s then
            s = s:gsub("%s+", "")
            s = s:gsub(ICONS_SUB_REGEX, "")
            return s
        end
    end)
    return db, schema
end

--- Find item under cursor and toggle it in the sidebar
---@param num integer row position
---@param val string exact name including whitespace
---@param sub_val string cleaned name without icons
local function toggleSelectionUnderCursor(num, val, sub_val)
    if sub_val == "Buffers" then
        UI.buffers_expanded = not UI.buffers_expanded
        UI:refreshSidebar()
        return
    end

    local is_folder, _ = string.find(val, UI_ICONS.folder)
    local db, schema = getDatabaseAndSchema(num)

    local con = UI.dbs[db]
    local con_schema = {}

    if con == nil then return end

    if sub_val == "Queries" then
        con.files_expanded = not con.files_expanded
    elseif con.dbms == "snowflake" and con.expanded then
        if db ~= sub_val then
            local sfdb = sidebarFind.snowflake_db(num)
            if con.schema[sfdb] then con_schema = con.schema[sfdb].schema[schema] end
        end
    else
        con_schema = con.schema[schema]
    end

    -- if item selected is first-layer database
    if db and db ~= schema and db == sub_val then
        if not con.loaded then con:connect() end
        toggleExpanded(UI.dbs, sub_val)
    -- Check all possibilities based on icon present in selected row in Sidebar
    elseif string.find(val, UI_ICONS.db2) then
        db = sidebarFind.snowflake_db(num)
        con.schema[db].expanded = not con.schema[db].expanded
    elseif string.find(val, UI_ICONS.tables) then
        con_schema.tables_expanded = not con_schema.tables_expanded
    elseif string.find(val, UI_ICONS.views) then
        con_schema.views_expanded = not con_schema.views_expanded
    elseif string.find(val, UI_ICONS.functions) then
        con_schema.functions_expanded = not con_schema.functions_expanded
    elseif string.find(val, UI_ICONS.procedures) then
        con_schema.procedures_expanded = not con_schema.procedures_expanded
    elseif sub_val == "Results" then
        UI.results_expanded = not UI.results_expanded
    elseif is_folder then
        toggleExpanded(con.files, sub_val)
    else
        -- deeper layer reached than first db layer
        local s = con.schema
        if con.dbms == "snowflake" then
            db = sidebarFind.snowflake_db(num)
            s = con.schema[db].schema
        end
        if string.find(val, UI_ICONS.schema) then
            if con.dbms == "snowflake" then
                local sfdb = con.schema[db].schema[sub_val]
                if not sfdb.expanded and not con.schema[db].schema[sub_val].functions_loaded then
                    local queries = require("sqlua.queries." .. con.dbms)
                    con:executeUv("refresh", {
                        "USE DATABASE " .. db .. ";",
                        queries.SchemaQuery(db, sub_val),
                    }, db)
                end
            end
            toggleExpanded(s, sub_val)
        elseif string.find(val, UI_ICONS.table) then
            toggleExpanded(s[schema].tables, sub_val)
        elseif string.find(val, UI_ICONS.view) then
            toggleExpanded(s[schema].views, sub_val)
        elseif string.find(val, UI_ICONS._function) then
            toggleExpanded(s[schema].functions, sub_val)
        elseif string.find(val, UI_ICONS.procedure) then
            toggleExpanded(s[schema].procedures, sub_val)
        end
    end
    UI:refreshSidebar()
end

---returns `nvim_win_get_cursor` and updates UI attributes
---@return integer[]
local function getCursorPos()
    local cursorPos = vim.api.nvim_win_get_cursor(0)
    UI.last_cursor_position.sidebar = cursorPos
    return cursorPos
end

---returns raw value and value without icons
---@return string, string
local function getValueUnderCursor()
    local val = vim.api.nvim_get_current_line()
    local icons = val:gsub("[^" .. ICONS_SUB_STRING .. "]", "")
    val = val:gsub("%(%d*%)", "")
    val = val:gsub("%s+[^%w]+", "")
    -- trim
    val = val:gsub("^%s*(.-)%s*$", "%1")
    if val:find("%(") then val = val:sub(1, val:find("%(") - 1) end
    if val == "" then return end
    local sub_val = val:gsub(ICONS_SUB_REGEX, "")
    if icons ~= nil then val = icons .. val end
    return val, sub_val
end

---primary function to initially create the sidebar
---@return nil
local function createSidebar()
    local win = UI.windows.sidebar
    local buf = vim.api.nvim_create_buf(false, true)
    if win == nil then return end
    vim.api.nvim_buf_set_name(buf, "Sidebar")
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_width(0, 40)
    vim.api.nvim_clear_autocmds({
        event = { "BufWinEnter", "BufWinLeave", "BufEnter", "BufLeave" },
        buffer = buf,
    })
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    vim.api.nvim_set_option_value("wfw", true, { win = win })
    vim.api.nvim_set_option_value("wrap", false, { win = win })
    vim.api.nvim_set_option_value("number", false, { win = win })
    vim.api.nvim_set_option_value("cursorline", true, { win = win })
    vim.api.nvim_set_option_value("cursorlineopt", "line", { win = win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = win })

    vim.cmd(
        "syn match SQLuaTable /["
            .. UI_ICONS.db
            .. UI_ICONS.db2
            .. UI_ICONS.folder
            .. UI_ICONS.table
            .. UI_ICONS.tables
            .. UI_ICONS.file
            .. "]/"
    )
    vim.cmd("syn match SQLuaSchema /[" .. UI_ICONS.schema .. "]/")
    vim.cmd("syn match SQLuaDDL /[" .. UI_ICONS.table_stmt .. "]/")
    vim.cmd("syn match SQLuaFunction /[" .. UI_ICONS.functions .. UI_ICONS._function .. "]/")
    vim.cmd("syn match SQLuaNewQuery /[" .. UI_ICONS.views .. UI_ICONS.view .. UI_ICONS.new_query .. "]/")
    vim.cmd("syn match SQLuaBuffer /[" .. UI_ICONS.buffers .. UI_ICONS.procedure .. UI_ICONS.procedures .. "]/")
    vim.cmd("syn match Comment /[" .. UI_ICONS.expanded .. UI_ICONS.collapsed .. "]/")

    UI.buffers.sidebar = buf
    -- Keymaps local to the Sidebar
    -- toggle sidebar
    vim.api.nvim_set_keymap("n", "<leader>st", "", {
        callback = function()
            if UI.windows.sidebar ~= nil then
                vim.api.nvim_set_current_win(UI.windows.sidebar)
                vim.api.nvim_set_current_buf(UI.buffers.sidebar)
                vim.cmd(":hide")
                UI.windows.sidebar = nil
            else
                local new_win = vim.api.nvim_open_win(UI.buffers.sidebar, true, {
                    split = "left",
                    win = UI.windows.sidebar,
                })
                UI.windows.sidebar = new_win
                vim.api.nvim_win_set_width(new_win, 40)
            end
        end,
    })
    -- jump between sidebar and last buf
    vim.api.nvim_set_keymap("n", "<leader>sf", "", {
        callback = function()
            local curbuf = vim.api.nvim_get_current_buf()
            local sidebar_pos = UI.last_cursor_position.sidebar
            local editor_pos = UI.last_cursor_position.editor
            local result_pos = UI.last_cursor_position.result
            if not next(editor_pos) then editor_pos = { 1, 0 } end
            local _type, _ = getBufferType(curbuf)
            if _type == "sidebar" then
                local lastwin = UI.last_active_window
                vim.api.nvim_set_current_win(lastwin)
                local lastbuf, _ = getBufferType(UI.last_active_buffer)
                if lastbuf == "editor" then
                    vim.api.nvim_win_set_cursor(lastwin, editor_pos)
                elseif lastbuf == "result" then
                    vim.api.nvim_win_set_cursor(lastwin, result_pos)
                end
            elseif _type == "editor" or _type == "result" then
                local sidebarwin = UI.windows.sidebar
                if sidebarwin ~= nil then
                    vim.api.nvim_set_current_win(sidebarwin)
                    vim.api.nvim_win_set_cursor(sidebarwin, sidebar_pos)
                end
            end
        end,
    })
    -- toggle help
    vim.api.nvim_buf_set_keymap(buf, "n", "?", "", {
        callback = function()
            if not UI.help_toggled then UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(UI.windows.sidebar) end
            UI.help_toggled = not UI.help_toggled
            UI:refreshSidebar()
        end,
    })
    -- refresh sidebar
    vim.api.nvim_buf_set_keymap(buf, "n", "R", "", {
        callback = function()
            UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(0)
            local db = UI.dbs.active_db or ""
            if db == "" then
                local pos = vim.api.nvim_win_get_cursor(0)
                db = sidebarFind.database(pos[1])
            end
            local con = UI.dbs[db]
            local queries = require("sqlua.queries." .. con.dbms)
            local query = ""
            if con.dbms == "snowflake" then
                -- TODO: implement snowflake specific refresh
                -- query = string.gsub(queries.SchemaQuery(con.db, con.schema.name), "\n", " ")
            else
                query = string.gsub(queries.SchemaQuery, "\n", " ")
            end
            con:executeUv("refresh", query)
            UI:refreshSidebar()
        end,
    })
    -- add a file
    vim.api.nvim_buf_set_keymap(buf, "n", "a", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
            local text = vim.api.nvim_get_current_line()
            local is_folder = text:match(UI_ICONS.folder) ~= nil
            local is_file = text:match(UI_ICONS.file) ~= nil

            -- exit if not somewhere a file can be added
            if not is_folder and not is_file then return end

            local db, _ = sidebarFind.database(pos[1])
            text = text:gsub("%s+", "")
            text = text:gsub(ICONS_SUB_REGEX, "")
            local file = UI.dbs[db].files:find(text)
            local parent_path = ""
            local show_path = ""

            if file == nil and text == "Queries" then
                parent_path = Utils.concat({
                    vim.fn.stdpath("data"),
                    "sqlua",
                    db,
                })
                show_path = parent_path
            else
                if file.isdir then
                    parent_path = file.path
                else
                    parent_path = file.path:match(".*/"):sub(1, -2)
                end
                show_path = parent_path:match(db .. ".*")
            end
            -- TODO: add floating win for input
            local newfile = vim.fn.input("Create file: " .. show_path .. "/")
            local save_path = Utils.concat({ parent_path, newfile })
            vim.fn.writefile({}, save_path)
            UI.dbs[db].files:refresh()
            UI:refreshSidebar()
        end,
    })
    -- delete a file
    vim.api.nvim_buf_set_keymap(buf, "n", "d", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
            local text = vim.api.nvim_get_current_line()
            local db, _ = sidebarFind.database(pos[1])

            local is_folder = text:match(UI_ICONS.folder) ~= nil
            local is_file = text:match(UI_ICONS.file) ~= nil
            local is_dbout = text:match(UI_ICONS.dbout) ~= nil

            -- exit if not a file or dbout result
            if not is_folder and not is_file and not is_dbout then return end

            if is_folder or is_file then
                text = text:gsub("%s+", "")
                text = text:gsub(ICONS_SUB_REGEX, "")
                if text == "Queries" then return end
                local file = UI.dbs[db].files:find(text)
                local show_path = file.path:match(db .. ".*") or file.path
                local response = vim.fn.input("Are you sure you want to remove " .. show_path .. "? [Y/n]")
                if response == "Y" then
                    assert(os.remove(file.path))
                    UI.dbs[db].files:refresh()
                    UI:refreshSidebar()
                end
            else
                -- remove the entry from 'Results'
                local qnum = tonumber(string.match(text, "%d+"))
                table.remove(UI.dbs[db].queries, qnum)
                UI:refreshSidebar()
            end
        end,
    })
    -- set active db
    vim.api.nvim_buf_set_keymap(buf, "n", UI.options.keybinds.activate_db, "", {
        callback = function()
            local cursorPos = vim.api.nvim_win_get_cursor(0)
            local num = cursorPos[1]
            local db, _ = sidebarFind.database(num)
            if not db then return end
            UI.active_db = db
            UI:refreshSidebar()
            vim.api.nvim_win_set_cursor(0, cursorPos)
        end,
    })
    -- collapse to parent disregarding current collapsibility
    vim.api.nvim_buf_set_keymap(buf, "n", "O", "", {
        callback = function()
            local cursorPos = vim.api.nvim_win_get_cursor(0)
            local num = cursorPos[1]

            local val, sub_val = getValueUnderCursor()
            if val == nil or sub_val == nil then return end

            local parent, line_num = sidebarFind.first_parent(num)
            if parent == nil then return end

            local icons = parent:gsub("[^" .. ICONS_SUB_STRING .. "]", "")
            parent = parent:gsub("%(%d*%)", "")
            parent = parent:gsub("%s+[^%w]+", "")
            -- trim
            parent = parent:gsub("^%s*(.-)%s*$", "%1")
            if parent:find("%(") then parent = parent:sub(1, parent:find("%(") - 1) end
            local subbed_parent = parent:gsub(ICONS_SUB_REGEX, "")
            if icons ~= nil then parent = icons .. parent end

            -- already top-level
            if line_num == 1 then return end

            toggleSelectionUnderCursor(line_num + 1, parent, subbed_parent)
            vim.api.nvim_win_set_cursor(UI.windows.sidebar, { line_num + 1, cursorPos[1] })
        end,
    })
    -- toggle collapse/expand current tree
    vim.api.nvim_buf_set_keymap(buf, "n", "o", "", {
        callback = function()
            local cursorPos = vim.api.nvim_win_get_cursor(0)
            local num = cursorPos[1]

            local val, sub_val = getValueUnderCursor()
            if val == nil or sub_val == nil then return end

            local is_collapsed, _ = string.find(val, UI_ICONS.collapsed)
            local is_expanded, _ = string.find(val, UI_ICONS.expanded)
            if is_collapsed or is_expanded then
                toggleSelectionUnderCursor(num, val, sub_val)
            else
                local first_collapsible, line_num = sidebarFind.first_collapsible(num)
                if first_collapsible == nil then return end

                first_collapsible = first_collapsible:gsub("%s+", "")
                if first_collapsible:find("%(") then first_collapsible = first_collapsible:sub(1, first_collapsible:find("%(") - 1) end
                local subbed_first_collapsible = first_collapsible:gsub(ICONS_SUB_REGEX, "")

                toggleSelectionUnderCursor(line_num, first_collapsible, subbed_first_collapsible)
                vim.api.nvim_win_set_cursor(UI.windows.sidebar, { line_num + 1, cursorPos[1] })
            end
        end,
    })
    -- expand, collapse, and do stuff under cursor
    vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
        callback = function()
            local cursorPos = getCursorPos()
            local num = cursorPos[1]
            local num_lines = vim.api.nvim_buf_line_count(UI.buffers.sidebar)

            -- if on last line, choose value above
            if num == num_lines then
                local cursorCol = cursorPos[2]
                local newpos = { num - 1, cursorCol }
                UI.last_cursor_position.sidebar = cursorPos
                vim.api.nvim_win_set_cursor(UI.windows.sidebar, newpos)
            end

            -- raw and clean
            local val, sub_val = getValueUnderCursor()

            local is_collapsed, _ = string.find(val, UI_ICONS.collapsed)
            local is_expanded, _ = string.find(val, UI_ICONS.expanded)

            -- if togglable, simply toggle
            if is_collapsed or is_expanded then
                toggleSelectionUnderCursor(num, val, sub_val)
                return
            end

            -- check icon contents of sidebar line and act accordingly
            if string.find(val, UI_ICONS.new_query) then
                if #UI.windows.editors == 0 then recreateEditor() end
                local buffer = createEditor(UI.windows.editors[1])
                UI:refreshSidebar()
                vim.api.nvim_set_current_win(UI.windows.editors[1])
                vim.api.nvim_set_current_buf(buffer)
                return
            elseif string.find(val, UI_ICONS.buffers) then
                if #UI.windows.editors == 0 then recreateEditor() end
                local bufname = val:gsub(ICONS_SUB_REGEX, "")
                for _, ebuf in pairs(UI.buffers.editors) do
                    local editor_name = vim.api.nvim_buf_get_name(ebuf)
                    local split = Utils.splitString(editor_name, Utils.sep)
                    if bufname == split[#split] then
                        local ewin = UI.windows.editors[1]
                        vim.api.nvim_win_set_buf(ewin, ebuf)
                        vim.api.nvim_set_current_win(ewin)
                    end
                end
                return
            end

            local db, schema = getDatabaseAndSchema(num)
            local queries = require("sqlua.queries." .. UI.dbs[db].dbms)

            if string.find(val, UI_ICONS.file) then
                local file = val:gsub(ICONS_SUB_REGEX, "")
                openFileInEditor(db, file)
            elseif string.find(val, UI_ICONS.dbout) then
                local rbuf = UI.buffers.results
                local qnum = tonumber(string.match(val, "%d+"))
                db, _ = sidebarFind.database(num)
                if UI.windows.results == nil then
                    _, rbuf = UI:createResultsPane(UI.queries[qnum].results)
                end
                setSidebarModifiable(rbuf, true)
                vim.api.nvim_buf_set_lines(rbuf, 0, -1, false, UI.queries[qnum].results)
                setSidebarModifiable(rbuf, false)
            elseif string.find(val, UI_ICONS.view) then
                local sf_db, _ = sidebarFind.snowflake_db(num)
                local query = queries
                    .Views({
                        db = sf_db,
                        table = sub_val,
                        schema = schema,
                    })
                    :gsub("\n", " ")
                UI.dbs[db]:executeUv("query", query)
            elseif string.find(val, UI_ICONS._function) then
                local query = queries
                    .Functions({
                        table = sub_val,
                        schema = schema,
                    })
                    :gsub("\n", " ")
                UI.dbs[db]:executeUv("query", query)
            elseif string.find(val, UI_ICONS.procedure) then
                local query = queries
                    .Procedures({
                        table = sub_val,
                        schema = schema,
                    })
                    :gsub("\n", " ")
                UI.dbs[db]:executeUv("query", query)
            else
                -- likely "create table" statement
                -- double check all values needed to inject into SQL
                local tbl = nil
                schema = nil
                db = nil
                local database = nil

                tbl, _ = sidebarFind.table(num)
                schema, _ = sidebarFind.schema(num)
                db, _ = sidebarFind.database(num)

                -- early return if data not available; i.e., do nothing
                if not tbl or not schema or not db then return end

                database = db

                local dbms = UI.dbs[db].dbms
                if UI.dbs[db].dbms == "snowflake" then db = sidebarFind.snowflake_db(num) end

                if tbl then
                    tbl = tbl:gsub(ICONS_SUB_REGEX, "")
                    tbl = tbl:gsub("%s+", "")
                end
                if schema then
                    schema = schema:gsub(ICONS_SUB_REGEX, "")
                    schema = schema:gsub("%s+", "")
                end
                if db then
                    db = db:gsub(ICONS_SUB_REGEX, "")
                    db = db:gsub("%s+", "")
                end
                val = val:gsub(ICONS_SUB_REGEX, "")

                -- return if icon regex fails
                if not tbl or not schema or not db then return end

                createTableStatement(val, tbl, schema, database, db, dbms)
            end

            -- correctly set last cursor position:w
            if vim.api.nvim_get_current_buf() == UI.buffers.sidebar then
                if UI.help_toggled then
                    local pos = UI.last_cursor_position.sidebar
                    pos[1] = pos[1] - UI.help_length + 2
                    vim.api.nvim_win_set_cursor(0, UI.last_cursor_position.sidebar)
                else
                    vim.api.nvim_win_set_cursor(0, UI.last_cursor_position.sidebar)
                end
            end

            highlightSidebarNumbers()
        end,
    })
end

--- Primary UI setup
---@param config table
---@return nil
function UI:setup(config)
    self.options = config
    for _, buf in pairs(vim.api.nvim_list_bufs()) do
        vim.api.nvim_buf_delete(buf, { force = true, unload = false })
    end

    -- execute query keybind
    vim.api.nvim_set_keymap("", config.keybinds.execute_query, "", {
        callback = function()
            -- return if in sidebar or results
            local win = vim.api.nvim_get_current_win()
            local tobreak = true
            for _, w in pairs(self.windows.editors) do
                if win == w then tobreak = false end
            end

            local buf = vim.api.nvim_get_current_buf()
            for _, b in pairs(self.buffers.editors) do
                if buf == b then tobreak = false end
            end

            if tobreak then return end

            local mode = vim.api.nvim_get_mode().mode
            local db = self.dbs[self.active_db]
            db:execute(mode)
            self:refreshSidebar()
        end,
    })

    -- things to do on various existing events
    vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
        callback = function()
            local closed_buf = vim.api.nvim_get_current_buf()
            if not closed_buf == self.buffers.sidebar then
                local bufs = vim.api.nvim_list_bufs()
                for _, buf in pairs(bufs) do
                    if buf == closed_buf then vim.api.nvim_buf_delete(buf, { unload = true }) end
                end
                EDITOR_NUM = EDITOR_NUM - 1
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufLeave" }, {
        callback = function()
            local curwin = vim.api.nvim_get_current_win()
            local curbuf = vim.api.nvim_get_current_buf()
            if self.initial_layout_loaded then
                self.last_active_buffer = curbuf
                self.last_active_window = curwin
                local type, _ = getBufferType(curbuf)
                if type == nil then return end
                self.last_cursor_position[type] = vim.api.nvim_win_get_cursor(curwin)
            else
                self.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(curwin)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
        callback = function()
            local curwin = vim.api.nvim_get_current_win()
            if curwin == self.windows.sidebar then
                if self.buffers.sidebar == nil then return end
                vim.api.nvim_win_set_buf(curwin, self.buffers.sidebar)
            elseif curwin == self.windows.results then
                if self.buffers.results == nil then return end
                vim.api.nvim_win_set_buf(curwin, self.buffers.results)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved" }, {
        callback = function(ev)
            if ev.buf ~= self.buffers.sidebar then return end
            if not self.initial_layout_loaded then return end
            local pos = vim.api.nvim_win_get_cursor(0)
            pos[1] = math.max(pos[1], 2)
            pos[2] = math.max(pos[2], 1)
            if next(self.dbs) == nil then
                vim.api.nvim_win_set_cursor(0, { 1, 0 })
            else
                vim.api.nvim_win_set_cursor(0, pos)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "WinClosed" }, {
        callback = function(ev)
            if ev.file == tostring(UI.windows.results) then
                UI.windows.results = nil
            elseif ev.file == tostring(UI.windows.sidebar) then
                UI.windows.sidebar = nil
            else
                for i, w in pairs(UI.windows.editors) do
                    if ev.file == tostring(w) then table.remove(UI.windows.editors, i) end
                end
            end
        end,
    })

    -- custom highlights
    self.sidebar_ns = vim.api.nvim_create_namespace("SQLuaSidebar")
    local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment" })
    local str_hl = vim.api.nvim_get_hl(0, { name = "String" })
    local int_hl = vim.api.nvim_get_hl(0, { name = "Number" })
    local keyword_hl = vim.api.nvim_get_hl(0, { name = "Keyword" })
    local function_hl = vim.api.nvim_get_hl(0, { name = "Function" })
    local error_hl = vim.api.nvim_get_hl(0, { name = "Error" })
    vim.api.nvim_set_hl(0, "SQLuaFunction", { fg = error_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaTable", { fg = function_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaBuffer", { fg = int_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaNewQuery", { fg = keyword_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaDDL", { fg = int_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaSchema", { fg = str_hl.fg })
    vim.api.nvim_set_hl(0, "SQLua_active_db", { fg = str_hl.fg, bg = nil, bold = true })
    vim.api.nvim_set_hl(0, "SQLuaHelpKey", { fg = str_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaHelpText", { fg = comment_hl.fg })

    local sidebar_win = vim.api.nvim_get_current_win()
    self.windows.sidebar = sidebar_win
    vim.cmd("vsplit")
    local editor_win = vim.api.nvim_get_current_win()
    table.insert(self.windows.editors, editor_win)

    createEditor(editor_win)
    createSidebar()

    if vim.api.nvim_buf_is_valid(1) then vim.api.nvim_buf_delete(1, {}) end
end

---performs vim syntax highlighting on results pane
---@return nil
function UI.highlightResultsPane()
    local previous_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(UI.buffers.sidebar)
    local str_hl = vim.api.nvim_get_hl(0, { name = "String" })
    local int_hl = vim.api.nvim_get_hl(0, { name = "Number" })
    local null_hl = vim.api.nvim_get_hl(0, { name = "Comment" })
    local function_hl = vim.api.nvim_get_hl(0, { name = "Function" })
    local error_hl = vim.api.nvim_get_hl(0, { name = "Error" })
    vim.api.nvim_set_hl(0, "SQLuaString", { fg = str_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaNumber", { fg = int_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaDateTime", { fg = function_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaNull", { fg = null_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaBool", { fg = error_hl.fg })
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = {
            "match",
            "SQLuaString",
            "contained",
            "/\\s(NULL)\\|\\d\\+\\s[^\\-|]\\{-\\}\\s\\{-\\}[!-/:-{}\\s]\\+\\|\\s[!-/:;=-{}]\\+\\|/",
        },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaNumber", "contained", "/\\s\\d\\+\\s[^!-/:-{}]/he=e-1" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaNumber", "contained", "/\\s\\d\\+\\.\\d\\+/" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaDateTime", "contained", "/\\d\\+-\\d\\+-\\d\\+/" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaDateTime", "contained", "/\\d\\+:\\d\\+:\\d\\+/" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = {
            "match",
            "SQLuaDateTime",
            "contained",
            "/\\d\\+:\\d\\+:\\d\\+\\.\\{-\\}\\d\\+-\\{-\\}\\d\\+/",
        },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaBool", "contained", "/|\\s[tf]\\s/hs=s+1" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { "match", "SQLuaNull", "contained", "/<null>\\|NULL/" },
    }, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = {
            "region",
            "Normal",
            "skipwhite",
            'start="|\\n"',
            'skip="\\$\\n"',
            "matchgroup=None",
            "contains=SQLuaNumber,SQLuaString,SQLuaDateTime,SQLuaNull,SQLuaBool",
            'end="\\n$"',
        },
    }, {})
    vim.api.nvim_set_current_buf(previous_buf)
end

return UI
