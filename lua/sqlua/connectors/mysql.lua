local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Mysql : Connection
Mysql = Connection:new()


function Mysql:setup(name, url)
    self.name = name
    self.url = url
    self.dbms = "mariadb"
    self.cmd = "mariadb"
    self.cli_args = {}
    for k, v in pairs(self.connection_info) do
        if type(v) == "table" then
            if next(v) ~= nil then
                for _, item in pairs(v) do
                    table.insert(self.cli_args, " --"..item)
                end
            end
        elseif v ~= "" and k ~= "dbms" then
            table.insert(self.cli_args, "--"..k.."="..v)
        end
    end
    table.insert(self.cli_args, "-t") -- table output

    local queries = require("sqlua.queries."..self.dbms)
    self.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return self
end

function Mysql:cleanSchema(data)
	local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "%s", "")
        schema[i] = string.sub(schema[i], 2, -2)
        schema[i] = utils.splitString(schema[i], "|")
    end
    return schema
end


function Mysql:dbmsCleanResults(data)
    if string.find(data[1], "mysql%: %[Warning%]") then
        table.remove(data, 1)
    end
    return data
end

return Mysql
