local M = {}

M.SchemaQuery = [[
SELECT
    s.schema_name,
    COALESCE(t.table_name, '-')
FROM information_schema.schemata s
    LEFT JOIN information_schema.tables t
        ON t.table_schema = s.schema_name
ORDER BY 1
]]

return M
