---@alias buffer integer
---@alias window integer
---@alias namespace_id integer
---@alias iterator function

---@class UI
---@field connections_loaded boolean
---@field initial_layout_loaded boolean
---@field help_toggled boolean
---@field sidebar_ns namespace_id
---@field active_db string
---@field dbs table
---@field num_dbs integer
---@field buffers table<buffer|table<buffer>>
---@field windows table<window|table<window>>
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
	active_db = "",
	dbs = {},
	num_dbs = 0,
	buffers = {
		sidebar = 0,
		editors = {},
		results = {},
	},
	windows = {
		sidebar = 0,
		editors = {},
		results = {},
	},
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

local Connection = require("sqlua.connection")

local UI_ICONS = {
	db = " ",
	buffers = "",
	saved_queries = " ",
	schemas = " ",
	schema = "פּ ",
	-- schema = '󱁊 ',
	table = "藺",
	saved_query = " ",
	new_query = "璘 ",
	table_stmt = "離 ",
	-- table = ' ',
}

local ICONS_SUB = "[פּ󱁊藺璘離]"
local EDITOR_NUM = 0

---@param buf buffer
---@param val boolean
---@return nil
local function setSidebarModifiable(buf, val)
	vim.api.nvim_buf_set_option(buf, "modifiable", val)
end

---@param buf buffer
---@return string|nil, buffer|nil
---Searches existing buffers and returns the buffer type, and buffer number
local function getBufferType(buf)
	if UI.buffers.sidebar == buf then
		return "sidebar", UI.buffers.sidebar
	end
	for _, v in pairs(UI.buffers.editors) do
		if v == buf then
			return "editor", v
		end
	end
	for _, v in pairs(UI.buffers.results) do
		if v == buf then
			return "result", v
		end
	end
end

---@param t table
---@return iterator
---replaces pairs() by utilizing a sorted table
local function pairsByKeys(t, f)
	local a = {}
	for n in pairs(t) do
		table.insert(a, n)
	end
	table.sort(a, f)
	local i = 0
	local iter = function()
		i = i + 1
		if a[i] == nil then
			return nil
		else
			return a[i], t[a[i]]
		end
	end
	return iter
end

---@param table table table to begin the search at
---@param search string what to search for to toggle
---@return nil
--[[Recursively searches the given table to toggle the 'expanded'
  attribute for the given item.
]]
local function toggleExpanded(table, search)
	for key, value in pairs(table) do
		if key == search then
			table[search].expanded = not table[search].expanded
			return
		elseif type(value) == "table" then
			toggleExpanded(value, search)
		end
	end
end

---@param type string the type of table statement
---@param tbl string table
---@param schema string schema
---@param db string database
---@return nil
---Creates the specified statement to query the given table.
---Query is pulled based on active_db rdbms, and fills the available buffer.
local function createTableStatement(type, tbl, schema, db)
	local queries = require("sqlua/queries." .. UI.dbs[db].rdbms)
	local buf = UI.last_active_buffer
	local win = UI.last_active_window
	if buf == 0 then
		buf = UI.buffers.editors[1]
		win = UI.windows.editors[1]
	end
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, 0, {})
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	local stmt = {}
	local query = queries.getQueries(tbl, schema, UI.options.default_limit)[type]
	for line in string.gmatch(query, "[^\r\n]+") do
		table.insert(stmt, line)
	end
	vim.api.nvim_buf_set_lines(buf, 0, 0, 0, stmt)
	Connection.execute(UI.dbs[db].cmd)
end

---@return nil
function UI:refreshSidebar()
	---@param buf buffer
	---@param tables table
	---@param srow integer
	---@param db string
	---@return integer srow
	local function refreshTables(buf, tables, srow, db)
		local sep = "     "
		local queries = require("sqlua/queries." .. UI.dbs[db].rdbms)
		local statements = queries.ddl
		for table, _ in pairsByKeys(tables) do
			if tables[table].expanded then
				vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
					sep .. " " .. UI_ICONS.table .. table,
				})
				srow = srow + 1
				for _, stmt in pairsByKeys(statements) do
					vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
						sep .. "    " .. UI_ICONS.table_stmt .. stmt,
					})
					srow = srow + 1
				end
			else
				vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
					sep .. " " .. UI_ICONS.table .. table,
				})
				srow = srow + 1
			end
		end
		return srow
	end

	---@param buf buffer
	---@param db string
	---@param srow integer
	---@return integer srow
	local function refreshSchema(buf, db, srow)
		local sep = "   "
		for schema, _ in pairsByKeys(UI.dbs[db].schema) do
			if UI.dbs[db].schema[schema].expanded then
				if type(UI.dbs[db].schema[schema]) == "table" then
					vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
						sep .. " " .. UI_ICONS.schema .. schema,
					})
					srow = srow + 1
					local tables = UI.dbs[db].schema[schema].tables
					srow = refreshTables(buf, tables, srow, db)
				end
			else
				vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
					sep .. " " .. UI_ICONS.schema .. schema,
				})
				srow = srow + 1
			end
		end
		return srow
	end

	local buf = UI.buffers.sidebar
	local sep = " "
	setSidebarModifiable(buf, true)
	vim.api.nvim_buf_set_lines(UI.buffers.sidebar, 0, -1, 0, {})
	local winwidth = vim.api.nvim_win_get_width(UI.windows.sidebar)
	local helptext = "press ? to toggle help"
	local helpTextTable = {
		string.format("%+" .. winwidth / 2 - (string.len(helptext) / 2) .. "s%s", "", helptext),
		" a - set the active db",
		" <A-t> - toggle sidebar focus",
		" <leader>r - run query",
	}
	local setCursor = UI.last_cursor_position.sidebar
	local srow = 2
	if UI.help_toggled then
		UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(UI.windows.sidebar)
		vim.cmd("syn match SQLuaHelpKey /.*\\( -\\)\\@=/")
		vim.cmd("syn match SQLuaHelpText /\\(- \\).*/")
		vim.api.nvim_buf_set_lines(buf, 0, 0, 0, helpTextTable)
		vim.cmd("syn match SQLuaHelpText /^$/")
		srow = srow + #helpTextTable
		vim.api.nvim_buf_add_highlight(UI.buffers.sidebar, UI.sidebar_ns, "Comment", 0, 0, winwidth)
		setCursor[1] = setCursor[1] + #helpTextTable
	else
		vim.api.nvim_buf_set_lines(buf, 0, 0, 0, {
			string.format("%+" .. winwidth / 2 - (string.len(helptext) / 2) .. "s%s", "", helptext),
		})
		vim.api.nvim_buf_add_highlight(UI.buffers.sidebar, UI.sidebar_ns, "Comment", 0, 0, winwidth)
	end

	vim.api.nvim_set_current_win(UI.windows.sidebar)
	vim.cmd("syn match SQLua_active_db /" .. UI.active_db .. "$/")
	for db, _ in pairsByKeys(UI.dbs) do
		if UI.dbs[db].expanded then
			vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, { sep .. " " .. UI_ICONS.db .. db })
			srow = refreshSchema(buf, db, srow)
		else
			vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, { sep .. " " .. UI_ICONS.db .. db })
		end
		srow = srow + 1
		vim.api.nvim_buf_add_highlight(UI.buffers.sidebar, UI.sidebar_ns, "active_db", srow - 1, 10, string.len(db))
	end
	if not pcall(function()
		vim.api.nvim_win_set_cursor(UI.windows.sidebar, setCursor)
	end) then
		vim.api.nvim_win_set_cursor(UI.windows.sidebar, {
			math.min(srow, UI.last_cursor_position.sidebar[1] - #helpTextTable),
			math.max(2, UI.last_cursor_position.sidebar[2]),
		})
	end
	setSidebarModifiable(buf, false)
end

---@param con Connection
---Adds the Connection object to the UI's databases
function UI:add(con)
	-- local copy = vim.deepcopy(con)
	local db = con.name
	if not UI.active_db then
		UI.active_db = db
	end
	UI.dbs[db] = con
	for _ in pairs(UI.dbs[con.name].schema) do
		UI.dbs[db].num_schema = UI.dbs[db].num_schema + 1
	end
	UI.num_dbs = UI.num_dbs + 1
	setSidebarModifiable(UI.buffers.sidebar, false)
end

---@param type string the type to search for
---@param num integer the starting row to begin the search
---@return string db, integer num
--[[Searches the sidebar from the given starting point upwards
  for the given type, returning the first occurence of either
  table, schema, or db
]]
local function sidebarFind(type, num)
	if type == "table" then
		local tbl = nil
		while true do
			tbl = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, 0)[1]
			if not tbl then
				return
			elseif string.find(tbl, "") then
				break
			end
			num = num - 1
		end
		num = num - 1
		return tbl, num
	elseif type == "schema" then
		local schema = nil
		while true do
			schema = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, 0)[1]
			if string.find(schema, "   ") then
				break
			end
			num = num - 1
		end
		return schema, num
	elseif type == "database" then
		local db = nil
		while true do
			db = vim.api.nvim_buf_get_lines(UI.buffers.sidebar, num - 1, num, 0)[1]
			if string.find(db, "^ ", 1) or string.find(db, "^ ", 1) then
				db = db:gsub("%s+", "")
				db = db:gsub(ICONS_SUB, "")
				break
			end
			num = num - 1
		end
		return db, num
	end
	return
end

---@return nil
local function createSidebar()
	local win = UI.windows.sidebar
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, "Sidebar")
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
	vim.api.nvim_win_set_width(0, 40)
	vim.api.nvim_buf_set_option(buf, "modifiable", false)
	vim.api.nvim_win_set_option(win, "wfw", true)
	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "number", false)
	vim.api.nvim_win_set_option(win, "cursorline", true)
	vim.api.nvim_win_set_option(win, "cursorlineopt", "line")
	vim.api.nvim_win_set_option(win, "relativenumber", false)
	vim.cmd("syn match Function /[פּ藺璘]/")
	vim.cmd("syn match String /[פּ󱁊]/")
	vim.cmd("syn match Boolean /[離]/")
	vim.cmd("syn match Comment /[]/")
	UI.buffers.sidebar = buf
	vim.api.nvim_set_keymap("n", "<A-t>", "", {
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
				vim.api.nvim_set_current_win(sidebarwin)
				vim.api.nvim_win_set_cursor(sidebarwin, sidebar_pos)
			end
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", "?", "", {
		callback = function()
			UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(UI.windows.sidebar)
			UI.help_toggled = not UI.help_toggled
			UI:refreshSidebar()
		end,
	})
	vim.api.nvim_buf_set_keymap(buf, "n", UI.options.keybinds.activate_db, "", {
		callback = function()
			vim.cmd("syn match Normal /" .. UI.active_db .. "$/")
			local cursorPos = vim.api.nvim_win_get_cursor(0)
			local num = cursorPos[1]
			local db, _ = sidebarFind("database", num)
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
			if val == "" then
				return
			end
			local m1, _ = string.find(val, "")
			local m2, _ = string.find(val, "")
			if not m1 and not m2 then
				local tbl = nil
				local schema = nil
				local db = nil
				tbl, num = sidebarFind("table", num)
				schema, num = sidebarFind("schema", num)
				db, num = sidebarFind("database", num)
				val = val:gsub(ICONS_SUB, "")
				tbl = tbl:gsub("%s+", "")
				tbl = tbl:gsub(ICONS_SUB, "")
				schema = schema:gsub("%s+", "")
				schema = schema:gsub(ICONS_SUB, "")
				createTableStatement(val, tbl, schema, db)
			else
				local db = nil
				db, num = sidebarFind("database", num)
				-- val = val:gsub("[]", "")
				val = val:gsub(ICONS_SUB, "")
				if db and db == val then
					toggleExpanded(UI.dbs, val)
				else
					toggleExpanded(UI.dbs[db], val)
				end
				UI:refreshSidebar()
				vim.api.nvim_win_set_cursor(0, cursorPos)
			end
		end,
	})
end

---@param win window
---@return nil
local function createEditor(win)
	vim.api.nvim_set_current_win(win)
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_buf_set_name(buf, "Editor " .. EDITOR_NUM)
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	vim.cmd("setfiletype sql")
	table.insert(UI.buffers.editors, buf)
	if not UI.last_active_window or not UI.last_active_buffer then
		UI.last_active_buffer = buf
		UI.last_active_window = win
	end
	EDITOR_NUM = EDITOR_NUM + 1
end

---@param config table
---@return nil
function UI:setup(config)
	UI.options = config
	for _, buf in pairs(vim.api.nvim_list_bufs()) do
		vim.api.nvim_buf_delete(buf, { force = true, unload = false })
	end

	vim.api.nvim_create_autocmd({ "BufDelete", "BufHidden" }, {
		callback = function()
			local closed_buf = vim.api.nvim_get_current_buf()
			if not closed_buf == UI.buffers.sidebar then
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
			if UI.connections_loaded and UI.initial_layout_loaded then
				UI.last_active_buffer = curbuf
				UI.last_active_window = curwin
				local _type, val = getBufferType(curbuf)
                if _type == nil then
                    return
                end
				UI.last_cursor_position[_type] = vim.api.nvim_win_get_cursor(curwin)
			else
				UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(curwin)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "WinNew" }, {
		callback = function(ev)
			if ev.buf == 1 then
				return
			end
			createEditor(vim.api.nvim_get_current_win())
		end,
	})
	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		callback = function(ev)
			if ev.buf ~= UI.buffers.sidebar then
				return
			end
			if not UI.initial_layout_loaded then
				return
			end
			local pos = vim.api.nvim_win_get_cursor(0)
			pos[1] = math.max(pos[1], 2)
			pos[2] = math.max(pos[2], 1)
			vim.api.nvim_win_set_cursor(0, pos)
		end,
	})

	UI.sidebar_ns = vim.api.nvim_create_namespace("SQLuaSidebar")
	vim.api.nvim_set_hl(0, "SQLua_active_db", { fg = "#00ff00", bold = true })
	vim.api.nvim_set_hl(0, "SQLuaHelpKey", {
		fg = vim.api.nvim_get_hl_by_name("String", true).foreground,
	})
	vim.api.nvim_set_hl(0, "SQLuaHelpText", {
		fg = vim.api.nvim_get_hl_by_name("Comment", true).foreground,
	})

	local sidebar_win = vim.api.nvim_get_current_win()
	UI.windows.sidebar = sidebar_win
	vim.cmd("vsplit")
	local editor_win = vim.api.nvim_get_current_win()
	table.insert(UI.windows.editors, editor_win)

	createSidebar()
	createEditor(editor_win)
end

return UI
