local UI = {}
local Sidebar = {}

function UI:setup()
  for _, buf in pairs(vim.api.nvim_list_bufs()) do
    vim.api.nvim_buf_delete(buf, { force = true, unload = false })
  end
  local sidebar_win = vim.api.nvim_get_current_win()
  local cursorPos = vim.api.nvim_win_get_cursor(sidebar_win)
  vim.cmd('vsplit')
  local editor_win = vim.api.nvim_get_current_win()
  local sidebar_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(sidebar_buf, "Sidebar")
  vim.api.nvim_win_set_buf(sidebar_win, sidebar_buf)
  vim.api.nvim_set_current_win(sidebar_win)
  vim.api.nvim_win_set_width(0, 25)
  vim.api.nvim_buf_set_option(sidebar_buf, 'modifiable', false)
  vim.api.nvim_win_set_option(sidebar_win, 'number', false)
  vim.api.nvim_win_set_option(sidebar_win, 'relativenumber', false)
  vim.api.nvim_set_current_win(editor_win)
  local editor_buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(editor_buf, "Editor")
  vim.api.nvim_win_set_buf(editor_win, editor_buf)
  vim.api.nvim_win_set_cursor(editor_win, cursorPos)
  vim.cmd('set filetype=sql')
end

return UI
