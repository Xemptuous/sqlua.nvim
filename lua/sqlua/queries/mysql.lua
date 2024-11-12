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
FROM `]] .. args.schema .. "`." .. args.table .. "\n" .. [[
LIMIT ]] .. args.limit
end

M.Columns = function(args)
	return "DESCRIBE `" .. args.schema .. "`." .. args.table
end

M.Indexes = function(args)
	return "SHOW INDEX FROM `" .. args.schema .. "`." .. args.table
end

M.References = function(args)
	return [[
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
  AND kc.referenced_table_schema = ']] .. args.schema .. [['
  AND kc.referenced_table_name = ']] .. args.table .. [['
]]
end

M.PrimaryKeys = function(args)
	return [[
SHOW KEYS FROM `]] .. args.schema .. "`." .. args.table .. [[

WHERE key_name = 'PRIMARY'
]]
end

M.ForeignKeys = function(args)
	return [[
SHOW KEYS FROM `]] .. args.schema .. "`." .. args.table .. [[
WHERE key_name <> 'PRIMARY'
LIMIT ]] .. args.limit
end

M.Views = function(args)
	return [[
SELECT view_definition
FROM information_schema.views
WHERE table_schema = ']] .. args.schema .. [['
  AND table_name = ']] .. args.table .. "'"
end

M.Procedures = function(args)
	return [[
SELECT routine_definition
FROM information_schema.routines
WHERE routine_schema = ']] .. args.schema .. [['
  AND routine_name = ']] .. args.table .. [['
  AND routine_type = 'PROCEDURE'
]]
end

M.Functions = function(args)
	return [[
SELECT routine_definition
FROM information_schema.routines
WHERE routine_schema = ']] .. args.schema .. [['
  AND routine_name = ']] .. args.table .. [['
  AND routine_type = 'FUNCTION'
]]
end

return M
