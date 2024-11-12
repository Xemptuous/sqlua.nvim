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

M.Data = function(args)
	return [[
SELECT *
FROM ]] .. args.schema .. "." .. args.table .. "\n" .. [[
LIMIT ]] .. args.limit
end

M.Columns = function(args)
	return "\\d+ " .. args.schema .. "." .. args.table
end

M.PrimaryKeys = function(args)
	return [[
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
  AND tc.table_name = ']] .. args.table .. [['
  AND tc.table_schema = ']] .. args.schema .. [['
]]
end

M.Indexes = function(args)
	return [[
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
WHERE tablename = ']] .. args.table .. [['
  AND schemaname = ']] .. args.schema .. "'"
end

M.References = function(args)
	return [[
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
  AND ccu.table_name = ']] .. args.table .. [['
  AND ccu.table_schema = ']] .. args.schema .. [['
]]
end

M.ForeignKeys = function(args)
	return [[
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
  AND tc.table_name = ']] .. args.table .. [['
  AND tc.table_schema = ']] .. args.schema .. [['
]]
end

M.Views = function(args)
	return "\\d+ " .. args.schema .. "." .. args.table
end

M.Proceduires = function(args)
	return "\\df+ " .. args.schema .. "." .. args.table
end

M.Functions = function(args)
	return "\\df+ " .. args.schema .. "." .. args.table
end

return M
