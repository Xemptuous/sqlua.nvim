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
	"DDL",
}

---@param tbl string
---@param schema string
---@param limit integer
---@return string[]
M.getQueries = function(tbl, schema, limit)
	return {
		Data = [[
SELECT *
FROM ]] .. schema .. "." .. tbl .. [[
LIMIT ]] .. limit,

		Columns = [[
SELECT
    column_name, column_default, is_nullable, data_type
FROM information_schema.columns
WHERE table_name = ']] .. tbl .. [['
    AND table_schema = ']] .. schema .. [['
ORDER BY column_name
  ]],

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
SELECT *
FROM pg_indexes
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
        ON ccu.constraint_name = tc.constraint_name
WHERE constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = ']] .. tbl .. [['
    AND tc.table_schema = ']] .. schema .. [['
]],

		ForeignKeys = [[
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
        ON ccu.constraint_name = tc.constraint_name
WHERE constraint_type = 'FOREIGN KEY'
    AND ccu.table_name = ']] .. tbl .. [['
    AND tc.table_schema = ']] .. schema .. [['
]],

		DDL = [[
SELECT
    table_name,
    pg_size_pretty(pg_relation_size(quote_ident(table_name))),
    pg_relation_size(quote_ident(table_name))
FROM Information_schema.tables
WHERE table_schema = 'public'
ORDER BY 3 DESC;
]],
	}
end

return M
