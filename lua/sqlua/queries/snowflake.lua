local M = {}

M.SchemaQuery = function(db, schema)
    return [[
    SELECT
        'table' AS type,
        table_catalog,
        table_schema,
        COALESCE(table_name, '-')
    FROM information_schema.tables
    WHERE LOWER(table_type) LIKE '%table%'
      AND table_catalog = ']]..db..[['
      AND table_schema = ']]..schema..[['
    UNION
    SELECT
        'view' AS type,
        table_catalog,
        table_schema,
        COALESCE(table_name, '-')
    FROM information_schema.tables
    WHERE LOWER(table_type) LIKE '%view%'
      AND table_catalog = ']]..db..[['
      AND table_schema = ']]..schema..[['
    UNION
    SELECT
        'function' AS type,
        function_catalog,
        function_schema,
        function_name
    FROM information_schema.functions
    WHERE function_catalog = ']]..db..[['
      AND function_schema = ']]..schema..[['
    UNION
    SELECT
        'procedure' AS type,
        procedure_catalog,
        procedure_schema,
        procedure_name
    FROM information_schema.procedures
    WHERE procedure_catalog = ']]..db..[['
      AND procedure_schema = ']]..schema..[['
    ORDER BY 1, 2, 3, 4
]]
end

M.DatabaseQuery = [[
    SELECT database_name
    FROM information_schema.databases
]]

M.SchemataQuery = function(db)
    return [[
    SELECT schema_name
    FROM information_schema.schemata
    WHERE catalog_name = ']]..db.."'"
end

M.TableQuery = function(db, schema)
    return [[
        SELECT table_name
        FROM information_schema.tables
        WHERE table_catalog = ']]..db..[['
          AND table_schema = ']]..schema..[['
    ]]
end

M.ddl = {
	"Data",
	"Columns",
	"Primary Keys",
	"Indexes",
	"References",
	"Foreign Keys",
}

---@param tbl string
---@param schema string
---@param limit integer
---@return string[]
M.getQueries = function(tbl, schema, db, limit)
	return {
        Data = [[
SELECT *
FROM ]]..schema.."."..tbl.."\n"..[[
LIMIT ]]..limit,
		Columns = "DESCRIBE "..db.."."..schema.."."..tbl,
		PrimaryKeys = [[
SHOW KEYS FROM ]]..schema.."."..tbl..[[

WHERE key_name = 'PRIMARY'
]],
		Indexes = "SHOW INDEX FROM "..schema.."."..tbl,
		References = [[
SELECT
    kc.constraint_name,
    kc.table_schema,
    kc.table_name,
    kc.column_name,
    c.column_type,
    c.column_key,
    kc.referenced_table_schema foreign_schema,
    kc.referenced_table_name foreign_table
FROM information_schema.key_column_usage kc
    JOIN information_schema.columns c
        ON c.table_schema = kc.table_schema
       AND c.table_name = kc.table_name
       AND c.column_name = kc.column_name
WHERE kc.constraint_name <> 'PRIMARY'
  AND kc.referenced_table_schema = ']]..schema..[['
  AND kc.referenced_table_name = ']]..tbl..[['
]],
		ForeignKeys = [[
SHOW KEYS FROM ]]..schema.."."..tbl..[[

WHERE key_name <> 'PRIMARY'
]]
	}
end

return M
