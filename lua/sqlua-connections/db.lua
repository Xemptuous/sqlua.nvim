local DB = {}
local utils = require('sqlua.utils')


DB.connections_file =  utils.concat { vim.fn.stdpath("data"), 'sqlua', 'connections.json' }


DB.connect = function(name)
  local connections = DB.readConnection()
  for _, connection in pairs(connections) do
    if not name then
      return connection['url']
    elseif connection['name'] == name then
      P(connection)
      print(connection['name'])
      print(connection['url'])
      return connection['url']
    end
  end
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
