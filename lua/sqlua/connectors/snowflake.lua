local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Snowflake : Connection
Snowflake = Connection:new()


---@overload fun(name: string, url: string)
function Snowflake:setup(name, url)
    self.name = name
    self.url = url
    self.dbms = "snowflake"
    self.cmd = "snowsql"
    self.cli_args = {"--abort-detached-query"}

    local queries = require("sqlua.queries."..self.dbms)
    self.schema_query = string.gsub(queries.DatabaseQuery, "\n", " ")
    return self
end

---@overload fun(data: table<string>) : table<string>
function Snowflake:cleanSchema(data)
	local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema, 1)
    table.remove(schema)
    table.remove(schema)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "|", "")
        schema[i] = string.gsub(schema[i], "%s", "")
    end
    return schema
end

---@overload fun(data: string) : table
--- Takes string results and transforms them to a table of strings
function Snowflake:dbmsCleanResults(data)
    table.remove(data, 1)
    table.remove(data, 1)
    table.remove(data)
    return data
end

return Snowflake
