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
M.getQueries = function(tbl, schema, db, limit)
	return {
        Data = [[
SELECT *
FROM ]]..schema.."."..tbl.."\n"..[[
LIMIT ]]..limit,
		Columns = "\\d+ "..schema.."."..tbl,
		PrimaryKeys = [[
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreigntbl_name,
    ccu.column_name AS foreign_column_name,
    rc.update_rule,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.referential_constraints as rc
      ON tc.constraint_name = rc.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
WHERE constraint_type = 'PRIMARY KEY'
  AND tc.table_name = ']] .. tbl .. [['
  AND tc.table_schema = ']] .. schema .. [['
]],
		Indexes = [[
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    pgi.indexdef AS index_definition
FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
    JOIN pg_indexes pgi
        ON tc.constraint_name = pgi.indexname
WHERE tablename = ']] .. tbl .. [['
  AND schemaname = ']] .. schema .. "'",
		References = [[
SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.update_rule,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.referential_constraints as rc
      ON tc.constraint_name = rc.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON tc.constraint_name = ccu.constraint_name
WHERE constraint_type = 'FOREIGN KEY'
  AND ccu.table_name = ']] .. tbl .. [['
  AND ccu.table_schema = ']] .. schema .. [['
]],
		ForeignKeys = [[
SELECT DISTINCT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    ccu.table_name AS foreign_table_name,
    ccu.column_name AS foreign_column_name,
    rc.update_rule,
    rc.delete_rule
FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.referential_constraints as rc
      ON tc.constraint_name = rc.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON tc.constraint_name = ccu.constraint_name
WHERE constraint_type = 'FOREIGN KEY'
  AND tc.table_name = ']] .. tbl .. [['
  AND tc.table_schema = ']] .. schema .. [['
]],
	}
end

return M
