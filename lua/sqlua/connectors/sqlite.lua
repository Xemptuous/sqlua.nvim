local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Sqlite : Connection
Sqlite = Connection:new()

---@param name string
---@param url string
---@param options table
function Sqlite:setup(name, url, options)
    -- TODO: implement array of db's to attach in the connections.json
    -- and parse them out, then run ATTACH commands as precursors.
    -- Either that, or implement actual persistent connections

    ---@class Sqlite
    local s = Sqlite:new()
    s.name = name
    s.url = url
    s.dbms = "sqlite"
    s.cmd = "sqlite3"
    s.cli_args = {}
    table.insert(s.cli_args, url)      -- table output
    table.insert(s.cli_args, "-table") -- table output
    local queries = require("sqlua.queries." .. s.dbms)
    s.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return s
end

---@param data table raw information schema data
function Sqlite:cleanSchema(data)
    local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "%s", "")
        schema[i] = utils.splitString(schema[i], "|")
    end
    return schema
end

return Sqlite
