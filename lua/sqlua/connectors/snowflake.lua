local Connection = require("sqlua.connectors.base")
local utils = require("sqlua.utils")

---@class Snowflake : Connection
Snowflake = Connection:new()


---@overload fun(name: string, url: string)
function Snowflake:setup(name, url)
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
        "friendly=False"
    }

    local queries = require("sqlua.queries."..s.dbms)
    s.schema_query = string.gsub(queries.DatabaseQuery, "\n", " ")
    return s
end

function Snowflake:cleanSchema(data)
	local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "|", "")
        schema[i] = string.gsub(schema[i], "%s", "")
    end
    return schema
end

function Snowflake:cleanTables(data)
	local schema = utils.shallowcopy(data)
    table.remove(schema, 1)
    table.remove(schema)
    for i, _ in ipairs(schema) do
        schema[i] = string.gsub(schema[i], "%s", "")
        schema[i] = utils.splitString(schema[i], "|")
    end
    for _ = 1,6 do table.remove(schema, 1) end
    return schema
end

---@param data string
---@return table
--- Takes string results and transforms them to a table of strings
function Snowflake:baseCleanResults(data)
    local result = {}
    local i = 1
    for c in data:gmatch(string.format("([^%s]+)", '\n')) do
        result[i] = c
        i = i + 1
    end
    return result
end

---@param data table
---@param query_type string
--- dbms specific cleaning
function Snowflake:dbmsCleanResults(data, query_type)
    if query_type == "query" then
    else
        table.remove(data, 1)
        table.remove(data, 1)
        table.remove(data)
    end
    return data
end

---@param data table
---@param db string
---@return nil
--- Populates the Connection's schema based on the stdout
--- from executing the DBMS' SchemaQuery
function Snowflake:getSchema(data, db)
    print("##### DIRTY #####")
    P(data)
    local schema = self:cleanSchema(data)
    print("##### CLEAN #####")
    P(schema)
    -- local old_schema = nil
    -- if next(self.schema) ~= nil then
    --     old_schema = vim.deepcopy(self.schema)
    -- end

    -- on initial db connect
    if not self.schema.databases_loaded then
        self.num_databases = 0
        print("----------LOADING DATABASES----------")
        for _, database in pairs(schema) do
            if not self.schema[database] then
                self.schema[database] = vim.deepcopy(Connection.Database)
                self.schema[database].dbms = self.dbms
            end
            self.num_databases = self.num_databases + 1
        end
        self.schema.databases_loaded = true
        return
    end
    for _ = 1,6 do table.remove(schema, 1) end
    print("##### AFTER CLEAN #####")
    P(schema)
    print("DB: ", db)
    if not self.schema[db].schemata_loaded then
        print("----------LOADING SCHEMAS----------")
        for _, s in pairs(schema) do
            if not self.schema[db][s] then
                self.schema[db].num_schema = 0
                self.schema[db].schema[s] = vim.deepcopy(Connection.Schema)
                self.schema[db].schema[s].dbms = self.dbms
                self.schema[db].num_schema = self.schema[db].num_schema + 1
            end
        end
        self.schema[db].schemata_loaded = true
        return
    end

    schema = self:cleanTables(data)
    print("### TABLE SCHEMA ###")
    P(schema)
    print("----------LOADING TABLES----------")
    -- on db expand
	for i, _ in ipairs(schema) do
        print(i, _)
        local type = schema[i][1]
		local d = schema[i][2] -- database
		local s = schema[i][3] -- schema
		local t = schema[i][4] -- table/view/proc/func
        print(type, d, s, t)
        if not self.schema[d].schema[s] then
            self.schema[d].schema[s] = vim.deepcopy(Connection.Schema)
            self.num_schema = self.num_schema + 1
            self.schema[d].schema[s].dbms = self.dbms
		end
        local cur = self.schema[d].schema[s]
        if not cur.schemas_loaded then
            cur.schemas_loaded = true
        end
		if t ~= "-" then
            if type == "function" then
                cur.functions[t] = { expanded = false }
                cur.num_functions = cur.num_functions + 1
            elseif type == "table" then
                cur.tables[t] = { expanded = false }
                cur.num_tables = cur.num_tables + 1
            elseif type == "view" then
                cur.views[t] = { expanded = false }
                cur.num_views = cur.num_views + 1
            else
                cur.procedures[t] = { expanded = false }
                cur.num_procedures = cur.num_procedures + 1
            end
		end
	end
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
