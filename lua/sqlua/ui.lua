local UI = {}

local function toggleModifiable(buf)
  local opt = vim.api.nvim_buf_get_option(buf, 'modifiable')
  if opt then
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    return
  end
  vim.api.nvim_buf_set_option(buf, 'modifiable', true)
end

function UI:populateSidebar(db, data)
  local buf = UI.sidebar_buf
  toggleModifiable(buf)
  vim.api.nvim_buf_set_lines(buf, 1, 1, 0, {"  "})
  vim.api.nvim_buf_set_text(buf, 1, 2, -1, 2, {db})
  local schema = {}
  local schema_sep = {}
  for key, _ in pairs(data) do
    table.insert(schema, key)
    table.insert(schema_sep, "    ")
  end
  table.sort(schema)
  for _, k in ipairs(schema) do
  --   print(k)
    vim.api.nvim_buf_set_lines(buf, _ + 1, -1, 0, schema_sep)
    vim.api.nvim_buf_set_text(buf, _ + 1, 4, _ + 1, 4, {k})
  -- vim.api.nvim_buf_set_lines(buf, 2, 2, 0, schema)
  end
  toggleModifiable(buf)
  -- end
  -- local buf = UI.sidebar_buf
  -- vim.api.nvim_buf_set_lines(buf, 0, -1, 0, data)
end

local function createSidebar(win)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "Sidebar")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_current_win(win)
  vim.api.nvim_win_set_width(0, 30)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  UI.sidebar_buf = buf
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
