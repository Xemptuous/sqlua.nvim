local Json = require("json")
local DB = {}

connections_file = vim.fn.stdpath("data") .. '/connections.json'

function DB.connect()

end

DB.writeConnectionConfig = function(data)
  local file = io.open(connections_file, "w")
  if file then
    local contents = Json.encode(data)
    file:write(contents)
    io.close(file)
    return true
  end
  return false

end

DB.readConnectionConfig = function()
  local file = io.open(connections_file, "r")
  if file then
    local contents = file:read("*a")
    local config = Json.decode(contents)
    io.close(file)
    return config
  end
  return nil
end

return DB
