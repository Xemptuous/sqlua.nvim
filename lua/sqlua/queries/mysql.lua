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

return M
