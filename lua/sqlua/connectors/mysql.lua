local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Mysql : Connection
Mysql = Connection:new()

---@class Mysql
function Mysql:setup(name, url, options)
    local s = Mysql:new()
    s.name = name
    s.url = url
    s.dbms = "mariadb"
    s.cmd = "mariadb"
    s.cli_args = {}
    s.connection_info = s:parseUrl()
    for k, v in pairs(s.connection_info) do
        if type(v) == "table" then
            if next(v) ~= nil then
                for _, item in pairs(v) do
                    table.insert(s.cli_args, " --" .. item)
                end
            end
        elseif v ~= "" and k ~= "dbms" then
            table.insert(s.cli_args, "--" .. k .. "=" .. v)
        end
    end
    table.insert(s.cli_args, "-t") -- table output
    table.insert(s.cli_args, "--safe-updates")
    table.insert(s.cli_args, "--select-limit=" .. options.default_limit)
    local queries = require("sqlua.queries." .. s.dbms)
    s.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return s
end

---@param data table raw information schema data
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

---@param data table raw result data
---@param query_type string
function Mysql:dbmsCleanResults(data, query_type)
    if string.find(data[1], "mysql%: %[Warning%]") then table.remove(data, 1) end
    return data
end

return Mysql
