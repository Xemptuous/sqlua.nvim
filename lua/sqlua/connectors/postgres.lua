local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Postgres : Connection
Postgres = Connection:new()


function Postgres:setup(name, url)
    self.name = name
    self.url = url
    self.dbms = "postgres"
    self.cmd = "psql"
    self.cli_args = {
        self.url,
        "--pset=null=<null>",
        "--pset=footer=off",
        "--pset=border=2",
    }

    local queries = require("sqlua.queries."..self.dbms)
    self.schema_query = string.gsub(queries.SchemaQuery, "\n", " ")
    return self
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
