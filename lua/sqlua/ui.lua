local Connection = require('sqlua.connection')
local UI = {
  connections_loaded = false,
  initial_layout_loaded = false,
  last_cursor_position = {
    sidebar = {},
    editor = {},
    result = {}
  },
  sidebar_buf = nil,
  sidebar_ns = nil,
  editor_buf = nil,
  active_db = nil,
  dbs = {},
  buffers = {
    sidebar = nil,
    editors = {},
    results = {}
  },
  windows = {
    sidebar = nil,
    editors = {},
    results = {}
  },
  last_active_buffer = nil,
  current_active_buffer = nil,
  last_active_window = nil,
  current_active_window = nil,
}

local UI_ICONS = {
  db = ' ',
  buffers = '' ,
  saved_queries = ' ',
  schemas = ' ',
  -- schema = 'פּ ',
  schema = '󱁊 ',
  table = '藺',
  saved_query = ' ',
  new_query = '璘 ',
  table_stmt = '離 ',
  -- table = ' ',
}
local ICONS_STRING = "פּ󱁊藺璘離"
local ICONS_SUB = "[פּ󱁊藺璘離]"
local EDITOR_NUM = 0


local function setSidebarModifiable(buf, val)
  vim.api.nvim_buf_set_option(buf, 'modifiable', val)
end


local function getBufferType(buf)
  if UI.buffers.sidebar == buf then
    return 'sidebar', UI.buffers.sidebar
  end
  for _, v in pairs(UI.buffers.editors) do
    if v == buf then
      return 'editor', v
    end
  end
  for _, v in pairs(UI.buffers.results) do
    if v == buf then
      return 'result', v
    end
  end
end


local function pairsByKeys(t, f)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a, f)
  local i = 0
  local iter = function ()
    i = i + 1
    if a[i] == nil then return nil
    else return a[i], t[a[i]]
    end
  end
  return iter
end


local function toggleItem(table, search)
  for key, value in pairs(table) do
    if key == search then
      table[search].expanded = not table[search].expanded
      return
    elseif type(value) == 'table' then
      toggleItem(value, search)
    end
  end
end


local function createTableStatement(type, tbl, schema, db)
  local queries = require('sqlua/queries.postgres')
  -- local buf = UI.editor_buf
  -- local win = UI.editor_win
  local buf = UI.last_active_buffer
  local win = UI.last_active_window
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, 0, {})
  vim.api.nvim_win_set_cursor(win, {1, 0})
  local stmt = {}
  local query = queries.getQueries(tbl, schema, UI.options.default_limit)[type]
  for line in string.gmatch(query, "[^\r\n]+") do
    table.insert(stmt, line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, 0, 0, stmt)
  Connection.execute(UI.dbs[db].cmd)
end


function UI:refreshSidebar()
  local function refreshTables(buf, tables, srow)
    local sep = "      "
    local statements = {
      "Data",
      "Columns",
      "Primary Keys",
      "Indexes",
      "References",
      "Foreign Keys",
      "DDL"
    }
    for table, _ in pairsByKeys(tables) do
      if tables[table].expanded then
        vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
          sep.." "..UI_ICONS.table..table
        })
        srow = srow + 1
        for _, stmt in pairsByKeys(statements) do
          vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
            sep.."    "..UI_ICONS.table_stmt..stmt
          })
          srow = srow + 1
        end
      else
        vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
          sep.." "..UI_ICONS.table..table
        })
        srow = srow + 1
      end
    end
    return srow
  end


  local function refreshSchema(buf, db, srow)
    local sep = "    "
    for schema, _ in pairsByKeys(UI.dbs[db].schema) do
      if UI.dbs[db].schema[schema].expanded then
        if type(UI.dbs[db].schema[schema]) == 'table' then
          vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
            sep.." "..UI_ICONS.schema..schema
          })
          srow = srow + 1
          local tables = UI.dbs[db].schema[schema].tables
          srow = refreshTables(buf, tables, srow)
        end
      else
        vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
          sep.." "..UI_ICONS.schema..schema
        })
        srow = srow + 1
      end
    end
    return srow
  end

  local buf = UI.buffers.sidebar
  -- local buf = UI.buffers.sidebar
  local sep = "  "
  setSidebarModifiable(buf, true)
  vim.api.nvim_buf_set_lines(buf, 1, -1, 0, {})
  -- setting win for syn match
  vim.api.nvim_set_current_win(UI.windows.sidebar)
  vim.cmd('syn match active_db /'..UI.active_db..'$/')
  local srow = 2
  for db, _ in pairsByKeys(UI.dbs) do
    if UI.dbs[db].expanded then
      vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, {sep.." "..UI_ICONS.db..db})
      vim.api.nvim_buf_add_highlight(
        UI.buffers.sidebar,
        UI.sidebar_ns,
        'active_db',
        srow - 1,
        10,
        string.len(db)
      )
      srow = refreshSchema(buf, db, srow)
    else
      vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, {sep.." "..UI_ICONS.db..db})
      vim.api.nvim_buf_add_highlight(
        UI.buffers.sidebar,
        UI.sidebar_ns,
        'active_db',
        srow - 1,
        10,
        string.len(db)
      )
    end
    srow = srow + 1
  end
  setSidebarModifiable(buf, false)
end


function UI:add(con)
  local copy = vim.deepcopy(con)
  local db = copy.name
  if not UI.active_db then
    UI.active_db = db
  end
  UI.dbs[db] = copy
  for _ in pairs(UI.dbs[copy.name].schema) do
    UI.dbs[db].num_schema = UI.dbs[db].num_schema + 1
  end
  setSidebarModifiable(UI.buffers.sidebar, false)
end


local function sidebarFind(type, buf, num)
  if type == 'table' then
    local tbl = nil
    while true do
      tbl = vim.api.nvim_buf_get_lines(buf, num - 1, num, 0)[1]
      if not tbl then
        return
      elseif string.find(tbl, '') then
        break
      end
      num = num - 1
    end
    num = num - 1
    return tbl, num
  elseif type == 'schema' then
    local schema = nil
    while true do
      schema = vim.api.nvim_buf_get_lines(buf, num - 1, num, 0)[1]
      if string.find(schema, '    ') then
        break
      end
      num = num - 1
    end
    return schema, num
  elseif type == 'database' then
    local db = nil
    while true do
      db = vim.api.nvim_buf_get_lines(buf, num - 1, num, 0)[1]
      if string.find(db, '^  ', 1) or string.find(db, '^  ', 1) then
        db = db:gsub("%s+", "")
        db = db:gsub(ICONS_SUB , "")
        break
      end
      num = num - 1
    end
    return db, num
  end
end


local function createSidebar(win)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "Sidebar")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_width(0, 40)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_win_set_option(win, 'wfw', true)
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  vim.cmd('syn match Function /[פּ藺璘]/')
  vim.cmd('syn match String /[פּ󱁊]/')
  vim.cmd('syn match Boolean /[離]/')
  vim.cmd('syn match Comment /[]/')
  UI.buffers.sidebar = buf
  vim.api.nvim_set_keymap('n', '<A-t>', '', {
    callback = function()
      local curbuf = vim.api.nvim_get_current_buf()
      local sidebar_pos = UI.last_cursor_position.sidebar
      local editor_pos = UI.last_cursor_position.editor
      local result_pos = UI.last_cursor_position.result
      if not next(editor_pos) then
        editor_pos = {1, 0}
      end
      local _type, _ = getBufferType(curbuf)
      if _type == 'sidebar' then
        local lastwin = UI.last_active_window
        vim.api.nvim_set_current_win(lastwin)
        local lastbuf, _ = getBufferType(UI.last_active_buffer)
        if lastbuf == 'editor' then
          vim.api.nvim_win_set_cursor(lastwin, editor_pos)
        elseif lastbuf == 'result' then
          vim.api.nvim_win_set_cursor(lastwin, result_pos)
        end
      elseif _type == 'editor' or _type == 'result' then
        local sidebarwin = UI.windows.sidebar
        vim.api.nvim_set_current_win(sidebarwin)
        vim.api.nvim_win_set_cursor(sidebarwin, sidebar_pos)
      end
    end
  })
  vim.api.nvim_buf_set_keymap(buf, 'n', UI.options.keybinds.activate_db, "", {
    callback = function()
      vim.cmd('syn match Normal /'..UI.active_db..'$/')
      local cursorPos = vim.api.nvim_win_get_cursor(0)
      local num = cursorPos[1]
      local db, _ = sidebarFind('database', buf, num)
      UI.active_db = db
      UI:refreshSidebar()
      vim.api.nvim_win_set_cursor(0, cursorPos)
    end
  })
  -- expand and collapse
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '', {
    callback = function()
      local cursorPos = vim.api.nvim_win_get_cursor(0)
      local num = cursorPos[1]
      local val = vim.api.nvim_get_current_line()
      val = val:gsub("%s+", "")
      if val == "" then return end
      local m1, _ = string.find(val, '')
      local m2, _ = string.find(val, '')
      if not m1 and not m2 then
        local tbl = nil
        local schema = nil
        local db = nil
        tbl, num = sidebarFind('table', buf, num)
        schema, num = sidebarFind('schema', buf, num)
        db, num = sidebarFind('database', buf, num)
        val = val:gsub(ICONS_SUB , "")
        tbl = tbl:gsub("%s+", "")
        tbl = tbl:gsub(ICONS_SUB , "")
        schema = schema:gsub("%s+", "")
        schema = schema:gsub(ICONS_SUB , "")
        createTableStatement(val, tbl, schema, db)
      else
        local db = nil
        db, num = sidebarFind('database', buf, num)
        -- val = val:gsub("[]", "")
        val = val:gsub(ICONS_SUB , "")
        if db and db == val then
          toggleItem(UI.dbs, val)
        else
          toggleItem(UI.dbs[db], val)
        end
        UI:refreshSidebar()
        vim.api.nvim_win_set_cursor(0, cursorPos)
      end
    end
  })
end


local function createEditor(win)
  vim.api.nvim_set_current_win(win)
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "Editor "..EDITOR_NUM)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, {1, 0})
  vim.cmd('setfiletype sql')
  table.insert(UI.buffers.editors, buf)
  if not UI.last_active_window or not UI.last_active_buffer then
    UI.last_active_buffer = buf
    UI.last_active_window = win
  end
  -- UI.editor_buf = buf
  EDITOR_NUM = EDITOR_NUM + 1
end


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
    end
  })
  vim.api.nvim_create_autocmd({ "BufLeave" }, {
    callback = function()
      local curwin = vim.api.nvim_get_current_win()
      local curbuf = vim.api.nvim_get_current_buf()
      if UI.connections_loaded and UI.initial_layout_loaded then
        UI.last_active_buffer = curbuf
        UI.last_active_window = curwin
        local _type, val = getBufferType(curbuf)
        UI.last_cursor_position[_type] = vim.api.nvim_win_get_cursor(curwin)
      else
        UI.last_cursor_position.sidebar = vim.api.nvim_win_get_cursor(curwin)
      end
    end
  })
  vim.api.nvim_create_autocmd({ "WinNew" }, {
    callback = function(ev)
      if ev.buf == 1 then
        return
      end
      createEditor(vim.api.nvim_get_current_win())
    end
  })

  UI.sidebar_ns = vim.api.nvim_create_namespace('SQLuaSidebar')
  vim.api.nvim_set_hl(0, 'active_db', {fg = "#00ff00", bold = true})

  local sidebar_win = vim.api.nvim_get_current_win()
  UI.windows.sidebar = sidebar_win
  vim.cmd('vsplit')
  local editor_win = vim.api.nvim_get_current_win()
  UI.editor_win = editor_win

  createSidebar(sidebar_win)
  createEditor(editor_win)
end


return UI
