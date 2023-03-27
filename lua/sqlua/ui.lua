local Connection = require('sqlua.connection')
local UI = {
  sidebar_buf = nil,
  editor_buf = nil,
  dbs = {},
}


local function setSidebarModifiable(buf, val)
  vim.api.nvim_buf_set_option(buf, 'modifiable', val)
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
  local buf = UI.editor_buf
  local win = UI.editor_win
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
          sep.." "..table
        })
        srow = srow + 1
        for _, stmt in pairsByKeys(statements) do
          vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
            sep.."    "..stmt
          })
          srow = srow + 1
        end
      else
        vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
          sep.." "..table
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
            sep.." "..schema
          })
          srow = srow + 1
          local tables = UI.dbs[db].schema[schema].tables
          srow = refreshTables(buf, tables, srow)
        end
      else
        vim.api.nvim_buf_set_lines(buf, srow, srow, 0, {
          sep.." "..schema
        })
        srow = srow + 1
      end
    end
    return srow
  end

  local buf = UI.sidebar_buf
  local sep = "  "
  setSidebarModifiable(buf, true)
  vim.api.nvim_buf_set_lines(buf, 1, -1, 0, {})
  local srow = 2
  for db, _ in pairsByKeys(UI.dbs) do
    if UI.dbs[db].expanded then
      vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, {sep.." "..db})
      srow = refreshSchema(buf, db, srow)
    else
      vim.api.nvim_buf_set_lines(buf, srow - 1, srow - 1, 0, {sep.." "..db})
    end
    srow = srow + 1
  end
  setSidebarModifiable(buf, false)
end


function UI:add(con)
  local copy = vim.deepcopy(con)
  local db = copy.name
  UI.dbs[db] = copy
  for _ in pairs(UI.dbs[copy.name].schema) do
    UI.dbs[db].num_schema = UI.dbs[db].num_schema + 1
  end
  setSidebarModifiable(UI.sidebar_buf, false)
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
        db = db:gsub("[]", "")
        break
      end
      num = num - 1
    end
    return db, num
  end
end


local function createSidebar(win)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "Sidebar")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_width(0, 40)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  UI.sidebar_buf = buf
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '<CR>', {
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
        tbl = tbl:gsub("%s+", "")
        tbl = string.sub(tbl, 4)
        schema = schema:gsub("%s+", "")
        schema = string.sub(schema, 4)
        createTableStatement(val, tbl, schema, db)
      else
        local db = nil
        db, num = sidebarFind('database', buf, num)
        val = val:gsub("[]", "")
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
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "Editor")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_cursor(win, {1, 0})
  vim.cmd('set filetype=sql')
  UI.editor_buf = buf
end


function UI:setup(config)
  UI.options = { default_limit = config.default_limit }
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_delete(buf, { force = true, unload = false })
  end

  local sidebar_win = vim.api.nvim_get_current_win()
  UI.sidebar_win = sidebar_win
  vim.cmd('vsplit')
  local editor_win = vim.api.nvim_get_current_win()
  UI.editor_win = editor_win

  createSidebar(sidebar_win)
  createEditor(editor_win)
end


return UI
