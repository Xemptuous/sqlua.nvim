local utils = require('sqlua.utils')
local M = {}
local DB = {
  schema = {},
  last_query = {}
}

local schemaQuery = [["
SELECT table_schema, table_name
FROM information_schema.tables
"]]

M.connections_file =  utils.concat { vim.fn.stdpath("data"), 'sqlua', 'connections.json' }

local getPostgresSchema = function(data)
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
      DB.schema[schema_name] = {}
      seen[schema_name] = true
    end
    table.insert(DB.schema[schema_name], table_name)
  end
  DB.schema = schema
  -- P(DB)
  return schema
end


local createResultsPane = function(data)
  if M.schema ~= {} then
    getPostgresSchema(data)
  end
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, "ResultsBuf")
  -- vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(0, 10)
  vim.api.nvim_buf_set_lines(buf, 0, 0, 0, data)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.cmd('goto 1')
end


local function onStdout(job_id, data, event)
  if vim.fn.bufexists("ResultsBuf") == 1 then
    for _, buffer in pairs(vim.api.nvim_list_bufs()) do
      if vim.fn.bufname(buffer) == 'ResultsBuf' then
        vim.api.nvim_buf_delete(buffer, {force = true, unload = false})
      end
    end
  end
  createResultsPane(data)
end


function onEvent(job_id, data, event)
  if event == 'stderr' then
  elseif event == 'exit' then
    return DB
  else
  end
end


function M.executeQuery()
  local mode = vim.api.nvim_get_mode()['mode']
  print(mode)
  P(mode)
  local query = nil
  if mode == 'n' then
    query = vim.api.nvim_buf_get_lines(0, 0, -1, 0)
  elseif (mode == 'v') or (mode == 'V') or (mode == '\22') then
    local srow, scol = 0, 0
    if mode == 'V' then
      -- FIXME: only captures previous selection, not the current one
      -- might be neovim limitation (tried sending gv, doesn't work)
      srow, scol = unpack(vim.api.nvim_buf_get_mark(0, "<"))
      erow, ecol = unpack(vim.api.nvim_buf_get_mark(0, ">"))
      ecol = 1024
    else
      _, srow, scol, _ = unpack(vim.fn.getpos("."))
      _, erow, ecol, _ = unpack(vim.fn.getpos("v"))
      -- Block Visual Mode
      if mode == '\22' then
        local lines = vim.api.nvim_buf_get_lines( 0, 
          math.min(srow, erow)-1, 
          math.max(srow, erow), 0
        )
        query = {}
        start = math.min(scol, ecol)
        _end = math.max(scol, ecol)
        for _, line in ipairs(lines) do
          print(line)
          print(string.sub(line, start, _end))
          table.insert(query, string.sub(line, start, _end))
        end
      else 
        if srow < erow or (srow == erow and scol <= ecol) then
          query = vim.api.nvim_buf_get_text(0, srow-1, scol-1, erow-1, ecol, {})
        else
          query = vim.api.nvim_buf_get_text(0, erow-1, ecol-1, srow-1, scol, {})
        end
      end
    end
  end
  local keys = vim.api.nvim_replace_termcodes('<ESC>', true, false, true)
  vim.api.nvim_feedkeys(keys, 'm', false)
  P(query)
end


function M:connect(name)
  local connections = M.readConnection()
  for _, connection in pairs(connections) do
    if connection['name'] == name then
      query = string.gsub(schemaQuery, '\n', " ")
      local cmd = 'psql ' .. connection['url'] .. ' -c ' .. query
      table.insert(DB.last_query, query)

      local opts = {
        stdout_buffered = true,
        on_exit = onEvent,
        on_stdout = onStdout,
        on_stderr = onEvent,
        on_data = onEvent
      }
      -- get current shell
      local handle = io.popen('echo $SHELL')
      local shell = handle:read("*a")

      job = vim.fn.jobstart(cmd, opts)
    end
  end
end


M.writeConnection = function(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({json}, M.connections_file)
end


M.readConnection = function()
  local content = vim.fn.readfile(M.connections_file)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end


M.addConnection = function(url, name)
  local file = M.readConnection()
  table.insert(file, {url = url, name = name})
  M.writeConnection(file)
end


-- local parseUrl = function(url)
--   local db = string.gsub(
--     string.sub(url, string.find(url, "%w+:")),
--     "[:]", ""
--   )
--   local username = string.gsub(
--     string.sub(url, string.find(url, "//%w+:")),
--     "[/:]", ""
--   )
--   local password = string.gsub(
--     string.sub(url, string.find(url, ":[%w!@#%$%%%^&%*%(%)%-_=%+]+@")),
--     "[:@]", ""
--   )
--   local server = string.gsub(
--     string.sub(url, string.find(url, "@.+/")),
--     "[@/]", ""
--   )
--   local ip = ""
--   local port = ""
--   if server == "localhost" then
--     ip = "127.0.0.1"
--     port = "5432"
--   else
--     ip = string.sub(server, string.find(server, "+[:/]"))
--     port = string.sub(server, string.find(server, ":+"))
--   end
--   return {
--     db = db,
--     username = username,
--     password = password,
--     server = server,
--     ip = ip,
--     port = port
--   }
-- end

return M
