local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Snowflake : Connection
Snowflake = Connection:new()

function Snowflake:setup(name, url, options)
    ---@class Snowflake
    local s = Snowflake:new()
    s.name = name
    s.url = url
    s.dbms = "snowflake"
    s.cmd = "snowsql"
    s.cli_args = {
        "--noup",
        "--abort-detached-query",
        "-o",
        "friendly=False",
    }

    local queries = require("sqlua.queries." .. s.dbms)
    s.schema_query = string.gsub(queries.DatabaseQuery, "\n", " ")
    return s
end

---@param data table raw information schema data
function Snowflake:cleanSchema(data)
    local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema)
    if #schema <= 6 then return {} end
    local result = {}
    for i, _ in ipairs(schema) do
        local row = self:baseCleanResults(schema[i])
        local row_table = string.gsub(row[1], "%s", "")
        local values = utils.splitString(row_table, "|")

        table.insert(result, {
            type = string.lower(values[3]),
            database = values[4],
            schema = values[5],
            table = values[2],
        })
    end
    return result
end

--- dbms specific cleaning
---@param data table
---@param query_type string
function Snowflake:dbmsCleanResults(data, query_type)
    if query_type == "query" then
    else
        table.remove(data, 1)
        table.remove(data, 1)
        table.remove(data)
    end
    return data
end

function Snowflake:cleanTables(data)
    local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "%s", "")
        schema[i] = utils.splitString(schema[i], "|")
    end
    for _ = 1, 6 do
        table.remove(schema, 1)
    end
    return schema
end

--[[
Populates the Connection's schema based on the stdout from executing the DBMS' SchemaQuery.
Custom overload required for Snowflake
]]
---@param data table
---@param db string
---@return nil
function Snowflake:getSchema(data, db)
    -- TODO: handle updates
    -- local old_schema = nil
    -- if next(self.schema) ~= nil then
    --     old_schema = vim.deepcopy(self.schema)
    -- end

    -- on initial db connect
    if not self.schema.databases_loaded then
        local schema = self:cleanSchema(data)
        self.num_databases = 0
        for _, row in pairs(schema) do
            local d = row.database
            local s = row.schema
            local t = row.table

            -- populate databases
            if not self.schema[d] then
                self.schema[d] = vim.deepcopy(Connection.Database)
                self.schema[d].dbms = self.dbms
            end
            self.num_databases = self.num_databases + 1

            -- populate schema
            if not self.schema[d].schema[s] then
                self.schema[d].num_schema = 0
                self.schema[d].schema[s] = vim.deepcopy(Connection.Schema)
                self.schema[d].schema[s].dbms = self.dbms
            end
            self.schema[d].num_schema = self.schema[d].num_schema + 1

            local cur = self.schema[d].schema[s]
            -- populate tables/views/procs/funcs
            if row.type == "function" then
                cur.functions[t] = { expanded = false }
                cur.num_functions = cur.num_functions + 1
            elseif row.type == "table" then
                cur.tables[t] = { expanded = false }
                cur.num_tables = cur.num_tables + 1
            elseif row.type == "view" then
                cur.views[t] = { expanded = false }
                cur.num_views = cur.num_views + 1
            else
                cur.procedures[t] = { expanded = false }
                cur.num_procedures = cur.num_procedures + 1
            end
        end
        self.schema.databases_loaded = true
        return
    elseif not self.schema.functions_loaded then
        local schema = self:cleanTables(data)
        for _, row in pairs(schema) do
            local t = row[3]
            local d = row[2]
            local s = row[4]
            local n = row[5]
            local cur = self.schema[d].schema[s]
            if t == "procedure" then
                cur.procedures[n] = { expanded = false }
                cur.num_procedures = cur.num_procedures + 1
            elseif t == "function" then
                cur.functions[n] = { expanded = false }
                cur.num_functions = cur.num_functions + 1
                -- base case for metadata
                -- only check if only result
            elseif #schema == 1 then
                cur.is_empty = true
            end
            self.schema[d].schema[s].functions_loaded = true
        end
    end
    -- TODO: handle updates
    -- if old_schema ~= nil then
    --     for s, st in pairs(self.schema) do
    --         local old_s, new_s = old_schema[s], self.schema[s]
    --         if old_s and not new_s then
    --             self.schema[s] = st
    --         elseif new_s and not old_s then
    --             old_schema[s] = st
    --         end
    --         self.schema[s].expanded = old_schema[s].expanded
    --         local types = { "tables", "views", "functions", "procedures" }
    --         for _, type in pairs(types) do
    --             for i, tbl in pairs(self.schema[s][type]) do
    --                 local old = old_schema[s][type][i]
    --                 local new = self.schema[s][type][i]
    --                 if old and not new then
    --                     self.schema[s][type][i] = tbl
    --                 elseif new and not old then
    --                     old_schema[s][type][i] = tbl
    --                 end
    --                 self.schema[s][type][i].expanded =
    --                     old_schema[s][type][i].expanded
    --             end
    --             self.schema[s][type.."_expanded"] =
    --                 old_schema[s][type.."_expanded"]
    --         end
    --     end
    -- end
end

return Snowflake
