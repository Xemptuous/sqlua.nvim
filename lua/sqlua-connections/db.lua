local utils = require('sqlua.utils')
local DB = {
  name = "",
  url = "",
  username = "",
}


DB.connections_file =  utils.concat { vim.fn.stdpath("data"), 'sqlua', 'connections.json' }

DB.runjob = function()

end


local parseUrl = function(url)
  local db = string.gsub(
    string.sub(url, string.find(url, "%w+:")),
    "[:]", ""
  )
  local username = string.gsub(
    string.sub(url, string.find(url, "//%w+:")),
    "[/:]", ""
  )
  local password = string.gsub(
    string.sub(url, string.find(url, ":[%w!@#%$%%%^&%*%(%)%-_=%+]+@")),
    "[:@]", ""
  )
  local server = string.gsub(
    string.sub(url, string.find(url, "@.+/")),
    "[@/]", ""
  )
  local ip = ""
  local port = ""
  if server == "localhost" then
    ip = "127.0.0.1"
    port = "5432"
  else
    ip = string.sub(server, string.find(server, "+[:/]"))
    port = string.sub(server, string.find(server, ":+"))
  end
  return {
    db = db,
    username = username,
    password = password,
    server = server,
    ip = ip,
    port = port
  }
end

-- DB.connect = function(name)
function DB:connect(name)
  local connections = DB.readConnection()
  for _, connection in pairs(connections) do
    if connection['name'] == name then
      self.name = connection['name']
      self.url = connection['url']
      local params = parseUrl(self.url)
      self.db = params['db']
      self.username = params['username']
      self.password = params['password']
      self.server = params['server']
      self.ip = params['ip']
      self.port = params['port']
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
