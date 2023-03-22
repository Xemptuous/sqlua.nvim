local utils = require('sqlua.utils')
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

local function createTableStatement(type, tbl, schema)
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
    -- line = utils.removeEndWhitespace(line)
    print(line)
    table.insert(stmt, line)
  end
  vim.api.nvim_buf_set_lines(buf, 0, 0, 0, stmt)
  Connection:executeQuery()
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
function UI:refreshSidebar()
  local buf = UI.sidebar_buf
  local sep = "  "
  setSidebarModifiable(buf, true)
  vim.api.nvim_buf_set_lines(buf, 1, -1, 0, {})
  local srow = 2

  for db, _ in pairsByKeys(UI.dbs) do
    if UI.dbs[db].expanded then
      vim.api.nvim_buf_set_lines(buf, 1, 1, 0, {sep.." "..db})
      srow = refreshSchema(buf, db, srow)
      srow = srow + 1
    else
      vim.api.nvim_buf_set_lines(buf, 1, 1, 0, {sep.." "..db})
      srow = srow + 1
    end
  end
  setSidebarModifiable(buf, false)
end

function UI:populateSidebar(db, data)
  local buf = UI.sidebar_buf
  local next = next
  if next(UI.dbs) == nil then
    UI.dbs[db] = {
      expanded = false,
      num_schema = 0,
      schema = data
    }
    for _ in pairs(UI.dbs[db].schema) do
      UI.dbs[db].num_schema = UI.dbs[db].num_schema + 1
    end
  end
  UI:refreshSidebar()
  setSidebarModifiable(buf, false)
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
      local val = vim.api.nvim_get_current_line()
      val = val:gsub("%s+", "")
      local m1, _ = string.find(val, '')
      local m2, _ = string.find(val, '')
      if not m1 and not m2 then
        local table = nil
        local num = cursorPos[1]
        while true do
          table = vim.api.nvim_buf_get_lines(buf, num - 1, num, 0)[1]
          if string.find(table, '') then
            break
          end
          num = num - 1
        end
        num = num - 1
        local schema = nil
        while true do
          schema = vim.api.nvim_buf_get_lines(buf, num - 1, num, 0)[1]
          if string.find(schema, '    ') then
            break
          end
          num = num - 1
        end
        table = table:gsub("%s+", "")
        table = string.sub(table, 4)
        schema = schema:gsub("%s+", "")
        schema = string.sub(schema, 4)
        createTableStatement(val, table, schema)
      else
        val = val:gsub("", "")
        val = val:gsub("", "")
        toggleItem(UI.dbs, val)
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

function UI:setup(args)
  UI.options = { default_limit = args.default_limit }
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
