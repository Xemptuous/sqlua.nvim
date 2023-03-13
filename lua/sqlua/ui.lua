local UI = {
  sidebar_buf = nil,
  dbs = {},
}

local function setSidebarModifiable(buf, val)
  vim.api.nvim_buf_set_option(buf, 'modifiable', val)
end

local function sortDB()
  dbs = {}
  for db, _ in pairs(UI.dbs) do
    dbs[db] = {}
    for s, _ in pairs(UI.dbs[db].schema) do
      dbs[db][s] = {}
      for t, _ in pairs(UI.dbs[db].schema[s].tables) do
        table.insert(dbs[db][s], t)
      end
      table.sort(dbs[db][s])
    end
    table.sort(dbs[db])
  end
  return dbs
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

function UI:refreshSidebar()
  local buf = UI.sidebar_buf
  local sl = vim.api.nvim_buf_set_lines
  local st = vim.api.nvim_buf_set_text
  setSidebarModifiable(buf, true)
  sl(buf, 1, -1, 0, {})
  local s_start = 1
  for db, _ in pairsByKeys(UI.dbs) do
    sl(buf, 1, 1, 0, {"  "})
    st(buf, 1, 2, -1, 2, {db})
    if UI.dbs[db].expanded then
      for schema, _ in pairsByKeys(UI.dbs[db].schema) do
        if type(UI.dbs[db].schema[schema]) == 'table' then
          local t_start = UI.dbs[db].num_schema + 1
          sl(buf, s_start + 1, s_start + 1, 0, {"    "})
          st(buf, s_start + 1, 4, s_start + 1, 4, {schema})
          s_start = s_start + 1
          if UI.dbs[db].schema[schema].expanded then
          -- FIXME: get proper folding to work with inner schema
            for table, _ in pairsByKeys(UI.dbs[db].schema[schema].tables) do
              sl(buf, t_start + 1, -1, 0, {"      "})
              st(buf, t_start + 1, 6, t_start + 1, 6, {table})
              t_start = t_start + 1
            end
          end
        end
      end
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
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  UI.sidebar_buf = buf
  vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', '<CR>', {
    callback = function()
      local cursorPos = vim.api.nvim_win_get_cursor(0)
      local val = vim.api.nvim_get_current_line()
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

function UI:setup()
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
