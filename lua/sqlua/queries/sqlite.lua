local M = {}

M.SchemaQuery = [[
    SELECT type, schema, COALESCE(name, '-')
    FROM pragma_table_list
    ORDER BY 1, 2
]]

M.ddl = {
    "Data",
    "Columns",
    -- "Primary Keys",
    "Indexes",
    -- "References",
    -- "Foreign Keys",
}

M.Data = function(args)
    return [[
SELECT *
FROM ]] .. args.table .. "\n" .. [[
LIMIT ]] .. args.limit
end

M.Columns = function(args) return "PRAGMA table_info([" .. args.table .. "])" end
M.Indexes = function(args) return "PRAGMA index_list([" .. args.table .. "])" end
M.Functions = function(args) return "pragma function_list" end

return M
