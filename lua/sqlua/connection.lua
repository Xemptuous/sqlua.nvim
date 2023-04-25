local utils = require('sqlua.utils')
---@class Connections
---module class for various methods
local Connections = {}

---@class Connection
---@field expanded boolean sidebar expansion flag
---@field num_schema integer number of schema in this db
---@field name string locally defined db name
---@field url string full url to connect to the db
---@field cmd string query to execute
---@field rdbms string actual db name according to the url
---@field last_query table<string> last query executed
---@field schema table<table<table>> nested schema design for this db
---the primary object representing a single connection to a rdbms by url
local Connection = {
  expanded = false,
  num_schema = 0,
  name = "",
  url = "",
  cmd = "",
  rdbms = "",
  last_query = {},
  schema = {}
}


RUNNING_JOBS = {}
CONNECTIONS_FILE =  utils.concat {vim.fn.stdpath("data"), 'sqlua', 'connections.json'}


local schemaQuery = [["
SELECT table_schema, table_name
FROM information_schema.tables
"]]


---@param data table
---@return nil
---Gets the initial db structure for postgresql rdbms
function Connection:getPostgresSchema(data)
  Connection.rdbms = 'postgres'
  local schema = utils.shallowcopy(data)
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


---@param data table
---@return nil
---Takes query output and creates a 'Results' window & buffer
local function createResultsPane(data)
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  --TODO: new result window increments by 1 each time
  -- consider reusing same one per window
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "ResultsBuf")
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(0, 10)
  vim.api.nvim_buf_set_lines(buf, 0, -1, 0, data)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'number', false)
  vim.api.nvim_win_set_option(win, 'relativenumber', false)
  vim.cmd('goto 1')
  table.insert(require('sqlua.ui').buffers.results, buf)
  table.insert(require('sqlua.ui').windows.results, win)
end


---@param job_id integer
---@param data table
---@param event string<'stdout', 'stderr', 'exit'>
---@return nil
---Callback for general jobcontrol events
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
  end
end

---@param job_id integer
---@param data table
---@param event string<'stdout', 'stderr', 'exit'>
---@return nil
---Callback for Connection.connect() jobcontrol
local function onConnect(job_id, data, event)
  if event == 'stdout' then
    Connection:getPostgresSchema(data)
  elseif event == 'stderr' then
  elseif event == 'exit' then
    require("sqlua.ui"):add(Connection)
  else
  end
end

---@param cmd string
---@return nil
---Executes the given query (cmd).
---Optional 'mode' determines what is executed:
---  - 'n' - executes entire buffer
---  - 'v' - executes visual selection
---  - 'V' - executes visual line
---  - '^V' - executes visual block
Connections.execute = function(cmd, --[[optional mode string]]mode)
  if not cmd or type(cmd) == 'table' then
    local ui = require('sqlua.ui')
    if not ui.dbs[ui.active_db] then
      return
    end
    cmd = ui.dbs[ui.active_db].cmd
  end
  if not mode then
    mode = vim.api.nvim_get_mode().mode
  end
  local query = nil
  if mode == 'n' then
    query = vim.api.nvim_buf_get_lines(0, 0, -1, 0)
  elseif mode == 'V' then
    -- FIXME: only captures previous selection, not the current one
    -- might be neovim limitation (tried feeding esc & 'gv', doesn't work)
    local srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
    local erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
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
    local lines = vim.api.nvim_buf_get_lines(
      0,
      math.min(srow, erow) - 1,
      math.max(srow, erow),
      0
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
  local command = cmd..'"'.. table.concat(query, " ")..'"'
  local job = vim.fn.jobstart(command, opts)

  -- exit visual mode on run
  local keys = vim.api.nvim_replace_termcodes('<ESC>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)
end


---@param name string
---@return nil
---Initializes the connection to the DB, and inserts into UI.
---Required for any operations on the given db.
Connections.connect = function(name)
  local connections = Connections.read()
  for _, connection in pairs(connections) do
    if connection['name'] == name then
      -- TODO: deepcopy Connection here and pass variable
      -- to onConnect callback to allow async without the
      -- jobwait function.
      -- Need to figure out how to pass additional variable
      -- to the callback :(
      Connection.name = name
      local query = string.gsub(schemaQuery, '\n', " ")
      Connection.url = connection['url']
      Connection.cmd = 'psql ' .. connection['url'] .. ' -c '
      local cmd = Connection.cmd .. query
      table.insert(Connection.last_query, query)

      local opts = {
        stdin = "null",
        stdout_buffered = true,
        stderr_buffered = true,
        on_exit = onConnect,
        on_stdout = onConnect,
        on_stderr = onConnect,
        on_data = onConnect
      }
      table.insert(RUNNING_JOBS, vim.fn.jobstart(cmd, opts))
      local running = vim.fn.jobwait(RUNNING_JOBS, 5000)
    end
  end
end


---@return table<string, string>
---Reads the connection.json file and returns content as a table
Connections.read = function()
  local content = vim.fn.readfile(CONNECTIONS_FILE)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end

---@param data table<string, string>
---@return nil
---Writes the given table to the connections.json file.
---table is expected to be in json format
Connections.write = function(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({json}, CONNECTIONS_FILE)
end


---@param url string
---@param name string
---@return nil
---Adds the given url + name to the connections.json file
Connections.add = function(url, name)
  local file = Connections:read()
  table.insert(file, {url = url, name = name})
  vim.fn.mkdir(ROOT_DIR..'/name', "p")
  Connections.write(file)
end


return Connections
