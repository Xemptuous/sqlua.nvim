local UI = {
  sidebar_buf = nil,
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

local function createTableStatement(type, table)
  -- TODO: grab cursor position and text
  -- crawl up to closest expanded parent in sidebar
  -- use that name
  local buf = UI.sidebar_buf
  vim.api.nvim_buf_set_lines(buf, 0, 0, 0, {})
  if type == 'select' then
    vim.api.nvim_buf_set_lines(buf, 0, 0, 0, {
      "SELECT * FROM "..table.." LIMIT "..UI.options.default_limit
    })
  end
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
      val = val:gsub("", "")
      val = val:gsub("", "")
      toggleItem(UI.dbs, val:gsub("%s+", ""))
      UI:refreshSidebar()
      vim.api.nvim_win_set_cursor(0, cursorPos)
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
end

function UI:setup(args)
  UI.options = { default_limit = args.default_limit }
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_delete(buf, { force = true, unload = false })
  end

  local sidebar_win = vim.api.nvim_get_current_win()
  vim.cmd('vsplit')
  local editor_win = vim.api.nvim_get_current_win()

  createSidebar(sidebar_win)
  createEditor(editor_win)
end

return UI
