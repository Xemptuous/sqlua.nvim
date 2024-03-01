local M = {}

M.SchemaQuery = [[
    SELECT
        'table' AS type,
        s.schema_name,
        COALESCE(t.table_name, '-')
    FROM information_schema.schemata s
        LEFT JOIN information_schema.tables t
            ON t.table_schema = s.schema_name
    UNION
    SELECT
        'view' AS type,
        s.schema_name,
        COALESCE(v.table_name, '-')
    FROM information_schema.schemata s
        LEFT JOIN information_schema.views v
            ON v.table_schema = s.schema_name
    UNION
    SELECT
        LOWER(COALESCE(routine_type, 'function')) AS type,
        s.schema_name,
        COALESCE(r.routine_name, '-')
    FROM information_schema.schemata s
        LEFT JOIN information_schema.routines r
            ON r.routine_schema = s.schema_name
    WHERE s.schema_name NOT IN ('pg_catalog', 'information_schema')
    UNION ALL
    SELECT
        LOWER(COALESCE(routine_type, 'procedure')) AS type,
        s.schema_name,
        COALESCE(r.routine_name, '-')
    FROM information_schema.schemata s
        LEFT JOIN information_schema.routines r
            ON r.routine_schema = s.schema_name
    WHERE s.schema_name NOT IN ('pg_catalog', 'information_schema')
    ORDER BY 1, 2
]]

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
M.getQueries = function(tbl, schema, limit)
	return {
        Data = [[
SELECT *
FROM ]]..schema.."."..tbl.."\n"..[[
LIMIT ]]..limit,
		Columns = "DESCRIBE "..schema.."."..tbl,
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
