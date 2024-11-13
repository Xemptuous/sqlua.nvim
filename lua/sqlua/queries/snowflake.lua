local M = {}
local utils = require("sqlua.utils")

M.SchemaQuery = function(db, schema)
	return [[
    SELECT
        'table' AS type,
        table_catalog,
        table_schema,
        COALESCE(table_name, '-')
    FROM information_schema.tables
    WHERE LOWER(table_type) LIKE '%table%'
      AND table_catalog = ']] .. db .. [['
      AND table_schema = ']] .. schema .. [['
    UNION
    SELECT
        'view' AS type,
        table_catalog,
        table_schema,
        COALESCE(table_name, '-')
    FROM information_schema.tables
    WHERE LOWER(table_type) LIKE '%view%'
      AND table_catalog = ']] .. db .. [['
      AND table_schema = ']] .. schema .. [['
    UNION
    SELECT
        'function' AS type,
        function_catalog,
        function_schema,
        function_name
    FROM information_schema.functions
    WHERE function_catalog = ']] .. db .. [['
      AND function_schema = ']] .. schema .. [['
    UNION
    SELECT
        'procedure' AS type,
        procedure_catalog,
        procedure_schema,
        procedure_name
    FROM information_schema.procedures
    WHERE procedure_catalog = ']] .. db .. [['
      AND procedure_schema = ']] .. schema .. [['
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
    WHERE catalog_name = ']] .. db .. "'"
end

M.TableQuery = function(db, schema)
	return [[
        SELECT table_name
        FROM information_schema.tables
        WHERE table_catalog = ']] .. db .. [['
          AND table_schema = ']] .. schema .. [['
    ]]
end

M.ddl = {
	"Data",
	"Columns",
	"Primary Keys",
	"Indexes",
	"References",
}

M.Data = function(args)
	return [[
SELECT *
FROM ]] .. utils.concat_ws(".", args.db, args.schema, args.table) .. "\n" .. [[
LIMIT ]] .. args.limit
end

M.Columns = function(args)
	return "DESCRIBE TABLE " .. utils.concat_ws(".", args.db, args.schema, args.table)
end

M.PrimaryKeys = function(args)
	return "SHOW PRIMARY KEYS IN TABLE " .. utils.concat_ws(".", args.db, args.schema, args.table)
end

M.Indexes = function(args)
	return "SHOW INDEXES IN TABLE " .. utils.concat_ws(".", args.db, args.schema, args.table)
end

M.References = function(args)
	return [[
SELECT *
FROM TABLE(GET_OBJECT_REFERENCES(
    DATABASE_NAME => ']] .. args.db .. [[',
    SCHEMA_NAME => ']] .. args.schema .. [[',
    OBJECT_NAME => ']] .. args.table .. [[')
)]]
end

M.Views = function(args)
	return [[
SELECT GET_DDL('VIEW', ']] .. utils.concat_ws(".", args.db, args.schema, args.table) .. "')"
end

return M
