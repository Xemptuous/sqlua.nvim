local utils = require('sqlua.utils')
local DB = {
  schema = {},
  last_query = {}
}

local schemaQuery = [[
"SELECT table_name
FROM information_schema.tables
WHERE NOT (table_schema = ANY('{pg_catalog, information_schema}'))"
]]

DB.connections_file =  utils.concat { vim.fn.stdpath("data"), 'sqlua', 'connections.json' }


local createResultsPane = function(data)
  local schema = utils.shallowcopy(data)
  for i, _ in pairs(schema) do
    schema[i] = string.gsub(schema[i], "%s", "")
  end
  if schema[1] == "table_name" then
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema)
    table.remove(schema)
    table.remove(schema)
  end
  DB.schema = schema
  vim.cmd('split')
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "ResultsBuf")
  P(vim.api.nvim_get_all_options_info())
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(0, 10)
  vim.api.nvim_buf_set_lines(buf, 0, 0, 0, schema)
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
  else
  end
end

function DB:connect(name)
  local connections = DB.readConnection()
  for _, connection in pairs(connections) do
    if connection['name'] == name then
      query = 'psql ' .. connection['url'] .. ' -c ' .. schemaQuery
      query = string.gsub(query, '\n', " ")

      local opts = {
        on_exit = onEvent,
        on_stdout = onStdout,
        on_stderr = onEvent,
        on_data = onEvent
      }
      -- get current shell
      local handle = io.popen('echo $SHELL')
      local shell = handle:read("*a")

      job = vim.fn.jobstart(shell, opts)
      vim.fn.chansend(job, {query, ''})
    end
  end
end


DB.writeConnection = function(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({json}, DB.connections_file)
end


DB.readConnection = function()
  local content = vim.fn.readfile(DB.connections_file)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end


DB.addConnection = function(url, name)
  local file = DB.readConnection()
  table.insert(file, {url = url, name = name})
  DB.writeConnection(file)
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

return DB
