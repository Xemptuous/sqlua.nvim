local utils = require('sqlua.utils')
local DB = {}
local queries = {}

schemaQuery = [[
"SELECT table_name
FROM information_schema.tables
WHERE NOT (table_schema = ANY('{pg_catalog, information_schema}'))"
]]

DB.connections_file =  utils.concat { vim.fn.stdpath("data"), 'sqlua', 'connections.json' }

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


function onStdout(job_id, data, event)
  table.insert(queries, data)
  P(data)
end


function onEvent(job_id, data, event)
  if event == 'stderr' then
  elseif event == 'exit' then
  else
  end
end

-- DB.connect = function(name)
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


DB.querySchema = function()
  
end


DB.writeConnection = function(data)
  local json = vim.fn.json_encode(data)
  vim.fn.writefile({json}, DB.connections_file)
end


DB.readConnection = function()
  local content = vim.fn.readfile(DB.connections_file)
  -- if not content then
  --   return nil
  -- end
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end


DB.addConnection = function(url, name)
  local file = DB.readConnection()
  table.insert(file, {url = url, name = name})
  DB.writeConnection(file)
end

return DB
