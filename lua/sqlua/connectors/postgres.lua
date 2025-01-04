local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Postgres : Connection
Postgres = Connection:new()

function Postgres:setup(name, url, options)
    ---@class Postgres
    local s = Postgres:new()
    s.name = name
    s.url = url
    s.dbms = "postgres"
    s.cmd = "psql"
    s.cli_args = {
        s.url,
        "--pset=null=<null>",
        "--pset=footer=off",
        "--pset=border=2",
    }

    local queries = require("sqlua.queries." .. s.dbms)
    s.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return s
end

function Postgres:cleanSchema(data)
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

return Postgres
