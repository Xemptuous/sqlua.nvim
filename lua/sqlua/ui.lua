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

-- ▾
-- ▸

function UI:refreshSidebar()
  local buf = UI.sidebar_buf
  local a = vim.api
  setSidebarModifiable(buf, true)
  a.nvim_buf_set_lines(buf, 1, -1, 0, {})
  local srow = 2

  for db, _ in pairsByKeys(UI.dbs) do
    if UI.dbs[db].expanded then
      a.nvim_buf_set_lines(buf, 1, 1, 0, {"   "..db})
      for schema, _ in pairsByKeys(UI.dbs[db].schema) do
        if UI.dbs[db].schema[schema].expanded then
          if type(UI.dbs[db].schema[schema]) == 'table' then
            a.nvim_buf_set_lines(buf, srow, srow, 0, {"     "..schema})
            srow = srow + 1
            for table, _ in pairsByKeys(UI.dbs[db].schema[schema].tables) do
              a.nvim_buf_set_lines(buf, srow, srow, 0, {"        "..table})
              srow = srow + 1
            end
          end
        else
          a.nvim_buf_set_lines(buf, srow, srow, 0, {"     "..schema})
          srow = srow + 1
        end
      end
      srow = srow + 1
    else
      a.nvim_buf_set_lines(buf, 1, 1, 0, {"   "..db})
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
      print(val)
      val = val:gsub("", "")
      val = val:gsub("", "")
      print(val)
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
