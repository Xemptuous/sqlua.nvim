local utils = require('sqlua.utils')
local Connection = {
  name = nil,
  url = nil,
  cmd = nil,
  last_query = {},
  dbs = {},
  schema = {},
  connections_file =  utils.concat {
    vim.fn.stdpath("data"), 'sqlua', 'connections.json'
  }
}


local schemaQuery = [["
SELECT table_schema, table_name
FROM information_schema.tables
"]]


-- local getPostgresSchema = function(data)
function Connection:getPostgresSchema(data)
  local schema = utils.shallowcopy(data)
  -- cleaning data
  table.remove(schema, 1)
  table.remove(schema, 1)
  table.remove(schema)
  table.remove(schema)
  table.remove(schema)
  local seen = {}
  for i, _ in ipairs(schema) do
    schema[i] = string.gsub(schema[i], "%s", "")
    schema[i] = utils.splitString(schema[i], "|")

    local schema_name = schema[i][1]
    local table_name = schema[i][2]
    if not seen[schema_name] then
      self.schema[schema_name] = {
        expanded = false,
        num_tables = 0,
        tables = {}
      }
      seen[schema_name] = true
    end
    self.schema[schema_name].num_tables = self.schema[schema_name].num_tables + 1
    self.schema[schema_name].tables[table_name] = {
      expanded = false
    }
  end
end


local function createResultsPane(data)
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "ResultsBuf")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(0, 10)
  vim.api.nvim_buf_set_lines(buf, 0, -1, 0, data)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.cmd('goto 1')
end


local function onEvent(job_id, data, event)
  local win = vim.api.nvim_get_current_win()
  local pos = vim.api.nvim_win_get_cursor(win)
  local buf = vim.api.nvim_win_get_buf(win)
  if (event == 'stdout') or (event == 'stderr') then
    if data[1] == "" then
      return
    end
    if vim.fn.bufexists("ResultsBuf") == 1 then
      for _, buffer in pairs(vim.api.nvim_list_bufs()) do
        if vim.fn.bufname(buffer) == 'ResultsBuf' then
          vim.api.nvim_buf_delete(buffer, {force = true, unload = false})
        end
      end
    end
    createResultsPane(data)
    vim.api.nvim_set_current_win(win)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_win_set_cursor(win, pos)
  elseif event == 'exit' then
  end
end


local function onConnect(job_id, data, event)
  if event == 'stdout' then
    Connection:getPostgresSchema(data)
  elseif event == 'stderr' then
  elseif event == 'exit' then
    table.insert(Connection.dbs, Connection)
    require("sqlua.ui"):populateSidebar(Connection.name, Connection.schema)
  else
  end
end


function Connection:executeQuery()
  local mode = vim.api.nvim_get_mode()['mode']
  local query = nil
  print(mode)
  if mode == 'n' then
    query = vim.api.nvim_buf_get_lines(0, 0, -1, 0)
  elseif mode == 'V' then
    -- FIXME: only captures previous selection, not the current one
    -- might be neovim limitation (tried feeding esc & 'gv', doesn't work)
    local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "'<"))
    local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, "'>"))
    ecol = 1024
    if srow < erow or (srow == erow and scol <= ecol) then
      query = vim.api.nvim_buf_get_text(0, srow-1, scol-1, erow-1, ecol, {})
    else
      query = vim.api.nvim_buf_get_text(0, erow-1, ecol-1, srow-1, scol, {})
    end
  elseif mode == 'v' then
    local _, srow, scol, _ = unpack(vim.fn.getpos("."))
    local _, erow, ecol, _ = unpack(vim.fn.getpos("v"))
      if srow < erow or (srow == erow and scol <= ecol) then
        query = vim.api.nvim_buf_get_text(0, srow-1, scol-1, erow-1, ecol, {})
      else
        query = vim.api.nvim_buf_get_text(0, erow-1, ecol-1, srow-1, scol, {})
      end
  elseif mode == '\22' then
    local _, srow, scol, _ = unpack(vim.fn.getpos("."))
    local _, erow, ecol, _ = unpack(vim.fn.getpos("v"))
    local lines = vim.api.nvim_buf_get_lines(0,
      math.min(srow, erow) -1,
      math.max(srow, erow), 0
    )
    query = {}
    local start = math.min(scol, ecol)
    local _end = math.max(scol, ecol)
    for _, line in ipairs(lines) do
      table.insert(query, string.sub(line, start, _end))
    end
  end
  local opts = {
    stdout_buffered = true,
    stderr_buffered = true,
    on_exit = onEvent,
    on_stdout = onEvent,
    on_stderr = onEvent,
    on_data = onEvent
  }
  local cmd = self.cmd.. '"' .. table.concat(query, " ") .. '"'
  local job = vim.fn.jobstart(cmd, opts)

  -- exit visual mode on run
  local keys = vim.api.nvim_replace_termcodes('<ESC>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)
end


function Connection:connect(name)
  local connections = Connection:readConnection()
  for _, connection in pairs(connections) do
    if connection['name'] == name then
      Connection.name = name
      local query = string.gsub(schemaQuery, '\n', " ")
      self.url = connection['url']
      self.cmd = 'psql ' .. connection['url'] .. ' -c '
      local cmd = self.cmd .. query
      table.insert(self.last_query, query)

      local opts = {
        stdout_buffered = true,
        stderr_buffered = true,
        on_exit = onConnect,
        on_stdout = onConnect,
        on_stderr = onConnect,
        on_data = onConnect
      }
      local job = vim.fn.jobstart(cmd, opts)
    end
  end
end


function Connection:writeConnection(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({json}, self.connections_file)
end


function Connection:readConnection()
  local content = vim.fn.readfile(self.connections_file)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end


function Connection:addConnection(url, name)
  local file = Connection:readConnection()
  table.insert(file, {url = url, name = name})
  Connection:writeConnection(file)
end


return Connection
