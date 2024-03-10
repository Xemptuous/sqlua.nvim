---@alias namespace_id integer
---@alias iterator function

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

---@class UI
---@field connections_loaded boolean
---@field initial_layout_loaded boolean
---@field help_toggled boolean
---@field sidebar_ns namespace_id
---@field active_db string
---@field dbs table
---@field num_dbs integer
---@field buffers Buffers
---@field windows Windows
---@field last_cursor_position table<table<integer, integer>>
---@field last_active_buffer buffer
---@field current_active_buffer buffer
---@field last_active_window window
---@field current_active_window window
local UI = {
	connections_loaded = false,
	initial_layout_loaded = false,
	help_toggled = false,
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
}

local Utils = require("sqlua.utils")

local UI_ICONS = {
    expanded = "",
    collapsed = "",
	db = "",
	buffers = "",
	folder = "",
	schemas = "",
	schema = "פּ",
	views = "󱇜",
	view = "",
	functions = "󰡱",
	_function = "󰊕",
	procedures = "󰯃",
	procedure = "󰯂",
	tables = "󰾇",
	table = "藺",
	file = "",
    results = "",
    dbout = "󰦨",
	new_query = "璘",
	table_stmt = "離",
}
UI_ICONS.icons_sub = function()
    local final = {}
    for _, icon in pairs(UI_ICONS) do
        if type(icon) == "string" then
            table.insert(final, icon)
        end
    end
    return "["..table.concat(final, "").."]"
end
local ICONS_SUB = UI_ICONS.icons_sub()
local EDITOR_NUM = 1

---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val)
	vim.api.nvim_set_option_value("modifiable", val, { buf = buf })
end

---Sets highlighting in the sidebar based on the hl
local function highlightSidebarNumbers()
	local buf = vim.api.nvim_win_get_buf(UI.windows.sidebar)
	local lines = vim.api.nvim_buf_get_lines(
        buf, 0, vim.api.nvim_buf_line_count(buf), false
    )
	for line, text in ipairs(lines) do
		local s = text:find("%s%(")
		local e = text:find("%)$")
		if s and e then
			vim.api.nvim_buf_add_highlight(
                UI.buffers.sidebar, UI.sidebar_ns, "Comment", line - 1, s, e
            )
		end
	end
end

---@param buf buffer
---@return string|nil, buffer|nil
---Searches existing buffers and returns the buffer type, and buffer number
local function getBufferType(buf)
	if UI.buffers.sidebar == buf then
		return "sidebar", UI.buffers.sidebar
    elseif UI.buffers.results == buf then
        return "result", buf
    end
	for _, v in pairs(UI.buffers.editors) do
		if v == buf then
			return "editor", v
		end
	end
end

---@param table table table to begin the search at
---@param search string what to search for to toggle
---@return nil
--[[Recursively searches the given table to toggle the 'expanded'
  attribute for the given item.
]]
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

---@param buf buffer
---@param srow integer
---@param text string
---@param sep string
---@return integer
local function printSidebarExpanded(buf, srow, text, sep)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, {
        sep..UI_ICONS.expanded.." "..text
    })
	return srow + 1
end

---@param buf buffer
---@param srow integer
---@param text string
---@param sep string
---@return integer
local function printSidebarCollapsed(buf, srow, text, sep)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, {
        sep..UI_ICONS.collapsed.." "..text
    })
	return srow + 1
end

---@param buf buffer
---@param srow integer
---@param text string
---@return integer
local function printSidebarEmpty(buf, srow, text)
	vim.api.nvim_buf_set_lines(buf, srow, srow, false, { text })
	return srow + 1
end

---@param type string the type of table statement
---@param tbl string table
---@param schema string schema
---@param db string database
---@return nil
---Creates the specified statement to query the given table.
---Query is pulled based on active_db dbms, and fills the available buffer.
local function createTableStatement(type, tbl, schema, db)
	local queries = require("sqlua/queries." .. UI.dbs[db].dbms)
    local win = UI.windows.editors[1]
    local buf = vim.api.nvim_win_get_buf(win)
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	local stmt = {}
	local query = queries.getQueries(
        tbl, schema, UI.options.default_limit
    )[type]
	for line in string.gmatch(query, "[^\r\n]+") do
		table.insert(stmt, line)
	end
	vim.api.nvim_buf_set_lines(buf, 0, 0, false, stmt)
    UI.dbs[db]:execute()
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
            tbl = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
            if not tbl then
                return
            elseif string.find(tbl, UI_ICONS.table) then
                break
            end
            num = num - 1
        end
        num = num - 1
        if tbl then
            if tbl:find("%(") then
                tbl = tbl:sub(1, tbl:find("%(") - 1)
            end
        end
        return tbl, num
    end,
    ---@param num integer sidebar starting line
    database = function(num)
        local db = nil
        while true do
            db = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
            if string.find(db, UI_ICONS.db) then
                db = db:gsub("%s+", "")
                db = db:gsub(ICONS_SUB, "")
                break
            end
            num = num - 1
        end
        if db then
            if db:find("%(") then
                db = db:sub(1, db:find("%(") - 1)
            end
        end
        return db, num
    end,
    ---@param num integer sidebar starting line
    schema = function(num)
        local schema = nil
        while true do
            schema = vim.api.nvim_buf_get_lines(
                UI.buffers.sidebar, num - 1, num, false
            )[1]
            if string.find(schema, UI_ICONS.schema) then
                break
            end
            num = num - 1
        end
        if schema then
            if schema:find("%(") then
                schema = schema:sub(1, schema:find("%(") - 1)
            end
        end
        return schema, num
    end
}


function UI:refreshSidebar()
	---@param buf buffer
	---@param srow integer
	---@param schema Schema
	---@param sep string
	---@return integer srow
	local function refreshTables(buf, srow, schema, sep)
		local queries = require("sqlua/queries." .. schema.dbms)
		local statements = queries.ddl

		local text = UI_ICONS.tables.." Tables ("..schema.num_tables..")"
		if schema.tables_expanded then
			srow = printSidebarExpanded(buf, srow, text, sep)
            for table, _ in Utils.pairsByKeys(schema.tables) do
                local txt = UI_ICONS.table.." "..table
                if schema.tables[table].expanded then
                    srow = printSidebarExpanded(buf, srow, txt, sep.."  ")
                    for _, stmt in Utils.pairsByKeys(statements) do
                        txt = UI_ICONS.table_stmt.." "..stmt
                        srow = printSidebarEmpty(buf, srow, sep.."      "..txt)
                    end
                else
                    srow = printSidebarCollapsed(buf, srow, txt, sep.."  ")
                end
            end
        else
			srow = printSidebarCollapsed(buf, srow, text, sep)
        end
		return srow
	end
	---@param buf buffer
	---@param srow integer
	---@param schema Schema
	---@param sep string
	---@return integer srow
	local function refreshViews(buf, srow, schema, sep)
		local v_text = UI_ICONS.views.." Views ("..schema.num_views..")"
		if schema.views_expanded then
			srow = printSidebarExpanded(buf, srow, v_text, sep)
            for view, _ in Utils.pairsByKeys(schema.views) do
                local text = UI_ICONS.view.." "..view
                srow = printSidebarEmpty(buf, srow, sep.."    "..text)
            end
        else
			srow = printSidebarCollapsed(buf, srow, v_text, sep)
        end
		return srow
	end
	---@param buf buffer
	---@param srow integer
	---@param schema Schema
	---@param sep string
	---@return integer srow
	local function refreshFunctions(buf, srow, schema, sep)
		local f_text = UI_ICONS.functions.." Functions ("
            ..schema.num_functions..")"
		if schema.functions_expanded then
			srow = printSidebarExpanded(buf, srow, f_text, sep)
            for fn, _ in Utils.pairsByKeys(schema.functions) do
                local text = UI_ICONS._function.." "..fn
                srow = printSidebarEmpty(buf, srow, sep.."    "..text)
            end
        else
			srow = printSidebarCollapsed(buf, srow, f_text, sep)
        end
		return srow
	end
	---@param buf buffer
	---@param srow integer
	---@param schema Schema
	---@param sep string
	---@return integer srow
	local function refreshProcedures(buf, srow, schema, sep)
		local p_text = UI_ICONS.procedures.." Procedures ("
            ..schema.num_procedures..")"
		if schema.procedures_expanded then
			srow = printSidebarExpanded(buf, srow, p_text, sep)
            for fn, _ in Utils.pairsByKeys(schema.procedures) do
                local text = UI_ICONS.procedure.." "..fn
                srow = printSidebarEmpty(buf, srow, sep.."    "..text)
            end
        else
			srow = printSidebarCollapsed(buf, srow, p_text, sep)
        end
		return srow
	end
	---@param buf buffer
	---@param file table
	---@param srow integer
	---@param sep string
	---@return integer srow
	local function refreshSavedQueries(buf, file, srow, sep)
        if file.isdir then
            local text = UI_ICONS.folder.. " " .. file.name
            if file.expanded then
                srow = printSidebarExpanded(buf, srow, text, sep)
                if next(file.files) ~= nil then
                    for _, f in Utils.pairsByKeys(file.files) do
                        srow = refreshSavedQueries(
                            buf, f, srow, sep .. "  "
                        )
                    end
                end
            else
                srow = printSidebarCollapsed(buf, srow, text, sep)
            end
        else
            local text = UI_ICONS.file.. " " .. file.name
            srow = printSidebarEmpty(buf, srow, sep .. "  " .. text)
        end
		return srow
	end
	---@param buf buffer
	---@param db string
	---@param srow integer
	---@return integer srow
	local function refreshSchema(buf, db, srow, sep)
        local s = self.dbs[db].schema
		for schema, _ in Utils.pairsByKeys(s) do
			local text = UI_ICONS.schema.." "..schema
            if type(s[schema]) == "table" then
                if s[schema].expanded then
					srow = printSidebarExpanded(buf, srow, text, sep)
                    local ns = sep .. "  "
					srow = refreshTables(buf, srow, s[schema], ns)
					srow = refreshViews(buf, srow, s[schema], ns)
					srow = refreshFunctions(buf, srow, s[schema], ns)
					srow = refreshProcedures(buf, srow, s[schema], ns)
                else
                    srow = printSidebarCollapsed(buf, srow, text, sep)
				end
			end
		end
		return srow
	end
	---@param buf buffer
	---@param db string
	---@param srow integer
	local function refreshDatabase(buf, db, srow)
		local sep = "   "

		local queries_text = UI_ICONS.folder.. " " .. "Queries"
		if self.dbs[db].files_expanded then
			srow = printSidebarExpanded(buf, srow, queries_text, sep)
            for _, file in Utils.pairsByKeys(self.dbs[db].files.files) do
                srow = refreshSavedQueries(
                    buf, file, srow, sep .. "  "
                )
            end
        else
			srow = printSidebarCollapsed(buf, srow, queries_text, sep)
        end

        srow = refreshSchema(buf, db, srow, sep)

        local dbout_text = UI_ICONS.results .. " " .. "Results ("
            .. #self.dbs[db].queries..")"
        if self.dbs[db].results_expanded then
			srow = printSidebarExpanded(buf, srow, dbout_text, sep)
            local query_results = {}
            for i, tbl in ipairs(self.dbs[db].queries) do
                local text = sep.."    "..UI_ICONS.dbout.." "..tostring(i)
                local stmt = table.concat(tbl.statement, "")
                table.insert(query_results, text.." ("..stmt..")")
            end
            for _, q in ipairs(Utils.reverse(query_results)) do
                srow = printSidebarEmpty(buf, srow, q)
            end
        else
			srow = printSidebarCollapsed(buf, srow, dbout_text, sep)
        end

		return srow
	end

	local sep = " "
    local setCursor = self.last_cursor_position.sidebar
    local srow = 2
	local buf = self.buffers.sidebar

    if buf == nil then
        return
    end

    local winwidth = vim.api.nvim_win_get_width(self.windows.sidebar)
    local helptext = "press ? to toggle help"
    local hl = string.len(helptext) / 2
    local helpTextTable = {
        string.format("%+" .. winwidth / 2 - (hl) .. "s%s", "", helptext),
        " a - add a file in the select dir",
        " d - delete the select file",
        " "..self.options.keybinds.activate_db.." - set the active db",
        " <C-t> - toggle sidebar focus",
        " "..self.options.keybinds.execute_query.." - run query",
    }

	setSidebarModifiable(buf, true)
	vim.api.nvim_buf_set_lines(self.buffers.sidebar, 0, -1, false, {})

    if self.help_toggled then
        vim.cmd("syn match SQLuaHelpKey /.*\\( -\\)\\@=/")
        vim.cmd("syn match SQLuaHelpText /\\(- \\).*/")
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, helpTextTable)
        vim.cmd("syn match SQLuaHelpText /^$/")
        srow = srow + #helpTextTable
        vim.api.nvim_buf_add_highlight(
            self.buffers.sidebar, self.sidebar_ns, "Comment", 0, 0, winwidth
        )
        setCursor[1] = setCursor[1] + #helpTextTable
    else
        vim.api.nvim_buf_set_lines(buf, 0, 0, false, {
            string.format("%+" .. winwidth / 2 - (hl) .. "s%s", "", helptext),
        })
        vim.api.nvim_buf_add_highlight(
            self.buffers.sidebar, self.sidebar_ns, "Comment", 0, 0, winwidth
        )
    end

    local new_query_text = UI_ICONS.new_query.. " " .. "New Editor"
    printSidebarEmpty(buf, srow - 1, sep..new_query_text)

    local buffers_text = UI_ICONS.schemas.. " " .. "Buffers"
    buffers_text = buffers_text.." ("..#self.buffers.editors..")"
    if self.buffers_expanded then
        srow = printSidebarExpanded(buf, srow, buffers_text, sep)
        for _, ebuf in Utils.pairsByKeys(self.buffers.editors) do
            local editor_name = vim.api.nvim_buf_get_name(ebuf)
            local split = Utils.splitString(editor_name, Utils.sep)
            local text = sep.."    "..UI_ICONS.buffers.." "..split[#split]
            srow = printSidebarEmpty(buf, srow, text)
        end
    else
        srow = printSidebarCollapsed(buf, srow, buffers_text, sep)
    end
    srow = srow + 1


	for db, _ in Utils.pairsByKeys(self.dbs) do
        if self.dbs[db].loaded then
            local ns = self.dbs[db].num_schema
            local text = UI_ICONS.db.." "..db.." (".. ns ..")"
            if self.dbs[db].expanded then
                printSidebarExpanded(buf, srow - 1, text, sep)
                srow = refreshDatabase(buf, db, srow)
            else
                printSidebarCollapsed(buf, srow - 1, text, sep)
            end
        else
            local text = UI_ICONS.db.." "..db
            printSidebarCollapsed(buf, srow - 1, text, sep)
        end
        srow = srow + 1
        if db == self.active_db then
            vim.cmd("syn match SQLua_active_db /"..db..".*$/")
        else
            vim.cmd("syn match Normal /"..db..".*$/")
        end
	end
	if not pcall(function()
        vim.api.nvim_win_set_cursor(self.windows.sidebar, setCursor)
    end) then
        local min = math.min(srow,
            self.last_cursor_position.sidebar[1] - #helpTextTable
        )
        local max = math.max(2, self.last_cursor_position.sidebar[2])
        if min <= 0 then min = 1 end
		vim.api.nvim_win_set_cursor(self.windows.sidebar, { min, max }) end
	highlightSidebarNumbers()
	setSidebarModifiable(buf, false)
end

---@param con Connection
---Adds the Connection object to the UI object
function UI:addConnection(con)
	local db = con.name
	if UI.active_db == "" then
		UI.active_db = db
	end
	UI.dbs[db] = con
    local files = vim.deepcopy(require("sqlua.files"))
    UI.dbs[db].files = files:setup(db)
	UI.num_dbs = UI.num_dbs + 1
	setSidebarModifiable(UI.buffers.sidebar, false)
end

local function openFileInEditor(db, filename)
    local path = UI.dbs[db].files:find(filename).path
    local existing_buf = nil
    for _, buffer in pairs(UI.buffers.editors) do
        local name = vim.api.nvim_buf_get_name(buffer)
        if name == path then
            existing_buf = buffer
        end
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


---@param data table
---@return nil
---Takes query output and creates a 'Results' window & buffer
function UI:createResultsPane(data)
	vim.cmd("split")
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_create_buf(false, true)
    self.buffers.results = buf
	self.windows.results = win
	vim.api.nvim_buf_set_name(buf, "ResultsBuf")
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
end

---@param win window
---@return buffer
local function createEditor(win)
    local name = Utils.concat({
        vim.fn.stdpath("data"),
        "sqlua",
        "Editor_"..EDITOR_NUM..".sql"
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


---@return nil
local function createSidebar()
	local win = UI.windows.sidebar
	local buf = vim.api.nvim_create_buf(false, true)
    if win == nil then
        return
    end
	vim.api.nvim_buf_set_name(buf, "Sidebar")
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_width(0, 40)
    vim.api.nvim_clear_autocmds({
        event={"BufWinEnter", "BufWinLeave", "BufEnter", "BufLeave"},
        buffer=buf
    })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	vim.api.nvim_set_option_value("wfw", true, { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", true, { win = win })
	vim.api.nvim_set_option_value("cursorlineopt", "line", { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.cmd("syn match SQLuaTable /[פּ藺璘󰾇]/")
	vim.cmd("syn match SQLuaSchema /[פּ󱁊]/")
	vim.cmd("syn match SQLuaDDL /[離]/")
	vim.cmd("syn match SQLuaFunction /[󰊕󰡱]/")
	vim.cmd("syn match SQLuaNewQuery /[璘󱇜]/")
	vim.cmd("syn match SQLuaBuffer /[󰯂󰯃]/")
	vim.cmd("syn match Comment /[]/")
	UI.buffers.sidebar = buf
	vim.api.nvim_set_keymap("n", "<C-t>", "", {
		callback = function()
			local curbuf = vim.api.nvim_get_current_buf()
			local sidebar_pos = UI.last_cursor_position.sidebar
			local editor_pos = UI.last_cursor_position.editor
			local result_pos = UI.last_cursor_position.result
			if not next(editor_pos) then
				editor_pos = { 1, 0 }
			end
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
	vim.api.nvim_buf_set_keymap(buf, "n", "?", "", {
		callback = function()
            if not UI.help_toggled then
                UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(
                    UI.windows.sidebar
                )
            end
			UI.help_toggled = not UI.help_toggled
			UI:refreshSidebar()
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "R", "", {
		callback = function()
			UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(0)
			for _, con in pairs(UI.dbs) do
                local queries = require('sqlua.queries.'..con.dbms)
                local query = string.gsub(queries.SchemaQuery, "\n", " ")
                con:executeUv("refresh", query)
                con.files:refresh()
			end
			UI:refreshSidebar()
		end,
	})
    vim.api.nvim_buf_set_keymap(buf, "n", "a", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
			local text = vim.api.nvim_get_current_line()
            local is_folder = text:match(UI_ICONS.folder) ~= nil
            local is_file = text:match(UI_ICONS.file) ~= nil
            if not is_folder and not is_file then
                return
            end
            local db, _ = sidebarFind.database(pos[1])
			text = text:gsub("%s+", "")
            text = text:gsub(ICONS_SUB, "")
            local file = UI.dbs[db].files:find(text)
            local parent_path = ""
            local show_path = ""
            if file == nil and text == "Queries" then
                parent_path = Utils.concat({
                    vim.fn.stdpath("data"), "sqlua", db
                })
                show_path = parent_path
            else
                if file.isdir then
                    parent_path = file.path
                else
                    parent_path = file.path:match(".*/"):sub(1, -2)
                end
                show_path = parent_path:match(db..".*")
            end
            -- TODO: add floating win for input
            local newfile = vim.fn.input("Create file: "..show_path.."/")
            local save_path = Utils.concat({parent_path, newfile})
            vim.fn.writefile({}, save_path)
            UI.dbs[db].files:refresh()
            UI:refreshSidebar()
        end
    })
    vim.api.nvim_buf_set_keymap(buf, "n", "d", "", {
        nowait = true,
        callback = function()
            local pos = vim.api.nvim_win_get_cursor(0)
			local text = vim.api.nvim_get_current_line()
            local db, _ = sidebarFind.database(pos[1])
            local is_folder = text:match(UI_ICONS.folder) ~= nil
            local is_file = text:match(UI_ICONS.file) ~= nil
            if not is_folder and not is_file then
                return
            end
			text = text:gsub("%s+", "")
            text = text:gsub(ICONS_SUB, "")
            if text == "Queries" then
                return
            end
            local file = UI.dbs[db].files:find(text)
            local show_path = file.path:match(db..".*")
            local response = vim.fn.input("Are you sure you want to remove "..show_path.."? [Y/n]")
            if response == "Y" then
                assert(os.remove(file.path))
                UI.dbs[db].files:refresh()
                UI:refreshSidebar()
            end
        end
    })
	vim.api.nvim_buf_set_keymap(buf, "n", UI.options.keybinds.activate_db, "", {
		callback = function()
			local cursorPos = vim.api.nvim_win_get_cursor(0)
			local num = cursorPos[1]
			local db, _ = sidebarFind.database(num)
			UI.active_db = db
			UI:refreshSidebar()
			vim.api.nvim_win_set_cursor(0, cursorPos)
		end,
	})
	-- expand and collapse
	vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
		callback = function()
			local cursorPos = vim.api.nvim_win_get_cursor(0)
			local num_lines = vim.api.nvim_buf_line_count(UI.buffers.sidebar)
			local num = cursorPos[1]
			-- if on last line, choose value above
			if num == num_lines then
				local cursorCol = cursorPos[2]
				local newpos = { num - 1, cursorCol }
				vim.api.nvim_win_set_cursor(UI.windows.sidebar, newpos)
			end

			local val = vim.api.nvim_get_current_line()
			val = val:gsub("%s+", "")
			if val:find("%(") then
				val = val:sub(1, val:find("%(") - 1)
			end
			if val == "" then
				return
			end


			local is_collapsed, _ = string.find(val, UI_ICONS.collapsed)
			local is_expanded, _ = string.find(val, UI_ICONS.expanded)
			if is_collapsed or is_expanded then
                local sub_val = val:gsub(ICONS_SUB, "")
                if sub_val == "Buffers" then
                    UI.buffers_expanded = not UI.buffers_expanded
                    UI:refreshSidebar()
                    vim.api.nvim_win_set_cursor(0, cursorPos)
                    return
                end
                local is_folder, _ = string.find(val, UI_ICONS.folder)
				local db, _ = sidebarFind.database(num)
                local _, schema = pcall(function()
                    local s = sidebarFind.schema(num)
                    if s then
                        s = s:gsub("%s+", "")
                        s = s:gsub(ICONS_SUB, "")
                        return s
                    end
                end)

                if db and db == sub_val then
                    if not UI.dbs[db].loaded then
                        UI.dbs[db]:connect()
                    end
					toggleExpanded(UI.dbs, sub_val)
				elseif sub_val == "Queries" then
					UI.dbs[db].files_expanded = not UI.dbs[db].files_expanded
                elseif string.find(val, UI_ICONS.tables) then
                    UI.dbs[db].schema[schema].tables_expanded = not
                    UI.dbs[db].schema[schema].tables_expanded
                elseif string.find(val, UI_ICONS.views) then
                    UI.dbs[db].schema[schema].views_expanded = not
                    UI.dbs[db].schema[schema].views_expanded
                elseif string.find(val, UI_ICONS.functions) then
                    UI.dbs[db].schema[schema].functions_expanded = not
                    UI.dbs[db].schema[schema].functions_expanded
                elseif string.find(val, UI_ICONS.procedures) then
                    UI.dbs[db].schema[schema].procedures_expanded = not
                    UI.dbs[db].schema[schema].procedures_expanded
                elseif sub_val == "Results" then
                    UI.dbs[db].results_expanded = not
                    UI.dbs[db].results_expanded
                elseif is_folder then
                    toggleExpanded(UI.dbs[db].files, sub_val)
				else
                    local s = UI.dbs[db].schema
                    if string.find(val, UI_ICONS.schema) then
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
				vim.api.nvim_win_set_cursor(0, cursorPos)
			else
				if string.find(val, UI_ICONS.file) then
					local file = val:gsub(ICONS_SUB, "")
					local db, _ = sidebarFind.database(num)
					openFileInEditor(db, file)
                elseif string.find(val, UI_ICONS.buffers) then
					local bufname = val:gsub(ICONS_SUB, "")
                    for _, ebuf in pairs(UI.buffers.editors) do
                        local editor_name = vim.api.nvim_buf_get_name(ebuf)
                        local split = Utils.splitString(editor_name, Utils.sep)
                        if bufname == split[#split] then
                            local ewin = UI.windows.editors[1]
                            vim.api.nvim_win_set_buf(ewin, ebuf)
                            vim.api.nvim_set_current_win(ewin)
                        end
                    end
                elseif string.find(val, UI_ICONS.new_query) then
                    local buffer = createEditor(UI.windows.editors[1])
                    UI:refreshSidebar()
                    vim.api.nvim_set_current_win(UI.windows.editors[1])
                    vim.api.nvim_set_current_buf(buffer)
                elseif string.find(val, UI_ICONS.dbout) then
                    -- TODO: after a while, these stop returning correct results
                    local rbuf= UI.buffers.results
                    if rbuf == nil then
                        return
                    end
                    local qnum = tonumber(string.match(val, "%d+"))
					local db, _ = sidebarFind.database(num)
                    setSidebarModifiable(rbuf, true)
                    vim.api.nvim_buf_set_lines(rbuf,
                        0, -1, false,
                        UI.dbs[db].queries[qnum].results
                    )
                    setSidebarModifiable(rbuf, false)
				else
					local tbl = nil
					local schema = nil
					local db = nil
					tbl, _ = sidebarFind.table(num)
					schema, _ = sidebarFind.schema(num)
					db, _ = sidebarFind.database(num)
                    if tbl then
                        tbl = tbl:gsub(ICONS_SUB, "")
                        tbl = tbl:gsub("%s+", "")
                    end
                    if schema then
                        schema = schema:gsub(ICONS_SUB, "")
                        schema = schema:gsub("%s+", "")
                    end
                    if db then
                        db = db:gsub(ICONS_SUB, "")
                        db = db:gsub("%s+", "")
                    end
					val = val:gsub(ICONS_SUB, "")
					if not tbl or not schema or not db then
						return
					end
					createTableStatement(val, tbl, schema, db)
				end
			end
			highlightSidebarNumbers()
		end,
	})
end

---@param config table
---@return nil
function UI:setup(config)
	self.options = config
	for _, buf in pairs(vim.api.nvim_list_bufs()) do
		vim.api.nvim_buf_delete(buf, { force = true, unload = false })
	end

	vim.api.nvim_set_keymap("", config.keybinds.execute_query, "", {
		callback = function()
            -- return if in sidebar or results
            local win = vim.api.nvim_get_current_win()
            local tobreak = true
            for _, w in pairs(self.windows.editors) do
                if win == w then
                    tobreak = false
                end
            end
            local buf = vim.api.nvim_get_current_buf()
            for _, b in pairs(self.buffers.editors) do
                if buf == b then
                    tobreak = false
                end
            end
            if tobreak then return end

			local mode = vim.api.nvim_get_mode().mode
            local db = self.dbs[self.active_db]
            db:execute(mode)
            self:refreshSidebar()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
		callback = function()
			local closed_buf = vim.api.nvim_get_current_buf()
			if not closed_buf == self.buffers.sidebar then
				local bufs = vim.api.nvim_list_bufs()
				for _, buf in pairs(bufs) do
					if buf == closed_buf then
						vim.api.nvim_buf_delete(buf, { unload = true })
					end
				end
				EDITOR_NUM = EDITOR_NUM - 1
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "BufLeave" }, {
		callback = function()
			local curwin = vim.api.nvim_get_current_win()
			local curbuf = vim.api.nvim_get_current_buf()
			if self.connections_loaded and self.initial_layout_loaded then
				self.last_active_buffer = curbuf
				self.last_active_window = curwin
				local type, _ = getBufferType(curbuf)
				if type == nil then
					return
				end
				self.last_cursor_position[type] =
                    vim.api.nvim_win_get_cursor(curwin)
			else
				self.last_cursor_position.sidebar =
                    vim.api.nvim_win_get_cursor(curwin)
			end
		end,
	})
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
        callback = function()
			local curwin = vim.api.nvim_get_current_win()
            if curwin == self.windows.sidebar then
                if self.buffers.sidebar == nil then
                    return
                end
                vim.api.nvim_win_set_buf(curwin, self.buffers.sidebar)
            elseif curwin == self.windows.results then
                if self.buffers.results == nil then
                    return
                end
                vim.api.nvim_win_set_buf(curwin, self.buffers.results)
            end
        end
    })
	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		callback = function(ev)
			if ev.buf ~= self.buffers.sidebar then
				return
			end
			if not self.initial_layout_loaded then
				return
			end
			local pos = vim.api.nvim_win_get_cursor(0)
			pos[1] = math.max(pos[1], 2)
			pos[2] = math.max(pos[2], 1)
            if next(self.dbs) == nil then
                vim.api.nvim_win_set_cursor(0, {1, 0})
            else
                vim.api.nvim_win_set_cursor(0, pos)
            end
		end,
	})

	self.sidebar_ns = vim.api.nvim_create_namespace("SQLuaSidebar")
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
	vim.api.nvim_set_hl(0, "SQLua_active_db", { fg = str_hl.fg, bold = true })
	vim.api.nvim_set_hl(0, "SQLuaHelpKey", { fg = str_hl.fg })
	vim.api.nvim_set_hl(0, "SQLuaHelpText", {
		fg = vim.api.nvim_get_hl(0, { name = "Comment" }).fg,
	})

	local sidebar_win = vim.api.nvim_get_current_win()
	self.windows.sidebar = sidebar_win
	vim.cmd("vsplit")
	local editor_win = vim.api.nvim_get_current_win()
	table.insert(self.windows.editors, editor_win)

	createEditor(editor_win)
	createSidebar()
    vim.api.nvim_buf_delete(1, {})
end

function UI.highlightResultsPane()
    local previous_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(UI.buffers.sidebar)
    local str_hl = vim.api.nvim_get_hl(0, { name = "String" })
    local int_hl = vim.api.nvim_get_hl(0, { name = "Number" })
    local null_hl = vim.api.nvim_get_hl(0, { name = "Comment" })
    local keyword_hl = vim.api.nvim_get_hl(0, { name = "Keyword" })
    local function_hl = vim.api.nvim_get_hl(0, { name = "Function" })
    local error_hl = vim.api.nvim_get_hl(0, { name = "Error" })
    vim.api.nvim_set_hl(0, "SQLuaString", { fg = str_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaNumber", { fg = int_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaDateTime", { fg = function_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaNull", { fg = null_hl.fg })
    vim.api.nvim_set_hl(0, "SQLuaBool", { fg = error_hl.fg })
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaString', 'contained',
            '/\\s(NULL)\\|\\d\\+\\s[^\\-|]\\{-\\}\\s\\{-\\}[!-/:-{}\\s]\\+\\|\\s[!-/:;=-{}]\\+\\|/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaNumber', 'contained',
            '/\\s\\d\\+\\s[^!-/:-{}]/he=e-1'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaNumber', 'contained',
            '/\\s\\d\\+\\.\\d\\+/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaDateTime', 'contained',
            '/\\d\\+-\\d\\+-\\d\\+/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaDateTime', 'contained',
            '/\\d\\+:\\d\\+:\\d\\+/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaDateTime', 'contained',
            '/\\d\\+:\\d\\+:\\d\\+\\.\\{-\\}\\d\\+-\\{-\\}\\d\\+/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaBool', 'contained',
            '/|\\s[tf]\\s/hs=s+1'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'match', 'SQLuaNull', 'contained',
            '/<null>\\|NULL/'
        }}, {})
    vim.api.nvim_cmd({
        cmd = "syntax",
        args = { 'region', 'Normal', 'skipwhite',
            'start="|\\n"',
            'skip="\\$\\n"',
            'matchgroup=None',
            'contains=SQLuaNumber,SQLuaString,SQLuaDateTime,SQLuaNull,SQLuaBool',
            'end="\\n$"',
        }}, {})
    vim.api.nvim_set_current_buf(previous_buf)
end

return UI
