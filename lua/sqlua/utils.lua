local M = {}

---@param v table
---@return table v
---prints the content of a given table
P = function(v)
    print(vim.inspect(v))
    return v
end

RELOAD = function(...) return require("plenary.reload").reload_module(...) end

R = function(name)
    RELOAD(name)
    return require(name)
end

M.sep = (function()
    ---@diagnostic disable-next-line: undefined-global
    if jit then
        ---@diagnostic disable-next-line: undefined-global
        local os = string.lower(jit.os)
        if os == "linux" or os == "osx" or os == "bsd" then
            return "/"
        else
            return "\\"
        end
    else
        -- return string.sub(package.config, 1, 1)
    end
end)()

---@param tbl table
---@return table
function M.reverse(tbl)
    for i = 1, math.floor(#tbl / 2), 1 do
        tbl[i], tbl[#tbl - i + 1] = tbl[#tbl - i + 1], tbl[i]
    end
    return tbl
end

--- Concatenate all objects passed in using OS fs separator
--- Ex:
--- `concat({
---     vim.fn.stdpath('data'),
---     'sqlua',
---     'connections.json'
--- })`
--- Returns:
--- `~/.local/share/nvim/sqlua/connections.json`
---@param ... table<string|string[]>
---@return string
function M.concat(...)
    local result = {}
    for _, i in pairs(...) do
        if type(i) == "table" then
            for _, j in pairs(i) do
                table.insert(result, j)
            end
        else
            table.insert(result, i)
        end
    end
    return table.concat(result, M.sep)
end

---Creates a shallow copy of a given table
---@param orig table
---@return table
M.shallowcopy = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == "table" then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

M.parse_jdbc = function (jdbc_str)
    -- Extract main components using pattern matching
    local subprotocol, authority, path, query = jdbc_str:match("^(%w+)://([^/]+)/([^?]*)%??(.*)")
    if not subprotocol then return nil, "Invalid JDBC format" end

    -- Initialize result table
    local result = {
        subprotocol = subprotocol,
        database = path,
        properties = {}
    }

    -- Parse authority section (user:password@host:port)
    local userinfo, hostport = authority:match("(.*)@(.*)")
    if userinfo then
        result.user, result.password = userinfo:match("([^:]*):?(.*)")
    else
        hostport = authority
    end

    -- Extract host and port
    result.host, result.port = hostport:match("([^:]+):?(%d*)$")
    result.port = result.port ~= "" and tonumber(result.port) or nil

    -- Parse query parameters
    for k, v in query:gmatch("([^&=]+)=([^&]*)") do
        result.properties[k] = v
    end

    return result
end

---Splits string by given delimiter and returns an array
---@param str string string
---@param separator string delimiter
---@return string[]
M.splitString = function(str, separator)
    if separator == nil then separator = "%s" end
    local t = {}
    for s in string.gmatch(str, "([^" .. separator .. "]+)") do
        table.insert(t, s)
    end
    return t
end

---Checks whether the given element is in the top level of the array/table
---@param arr table
---@param element any
---@return boolean
M.inArray = function(arr, element)
    for _, value in ipairs(arr) do
        if value == element then return true end
    end
    return false
end

---Returns a new table with duplicate values removed (top level only)
---@param arr table
---@return table
M.removeDuplicates = function(arr)
    local newArray = {}
    for _, element in ipairs(arr) do
        if not M.inArray(newArray, element) then table.insert(newArray, element) end
    end
    return newArray
end

---@param table table table to begin searching
---@param search_for any what to search for
---@param replacement any value to replace with
---@return nil
M.deepReplace = function(table, search_for, replacement)
    if not table then return end
    for key, value in pairs(table) do
        if type(value) == "table" then
            M.deep_replace(value, search_for, replacement)
        else
            table[key] = value:gsub(search_for, replacement)
        end
    end
end

---Trims leading and trailing whitespace
---@param line string
---@return string
M.removeEndWhitespace = function(line) return line:gsub("^%s*(.-)%s*$", "%1")[1] end

M.getFileName = function(path) return path:match("^.+/(.+)$") end

---@param file table|string the connections.json file
---@return table content json table object
M.getDatabases = function(file)
    local content = vim.fn.readfile(file)
    if next(content) == nil then return {} end
    content = vim.fn.json_decode(vim.fn.join(content, "\n"))
    return content
end

---replaces pairs() by utilizing a sorted table
---@param t table
---@return iterator
M.pairsByKeys = function(t, f)
    local a = {}
    for n in pairs(t) do
        table.insert(a, n)
    end
    table.sort(a, f)
    local i = 0
    local iter = function()
        i = i + 1
        if a[i] == nil then
            return nil
        else
            return a[i], t[a[i]]
        end
    end
    return iter
end

---@param sep string
---@return string
M.concat_ws = function(sep, ...)
    local r = {}
    for k, v in ipairs({ ... }) do
        r[#r + 1] = tostring(v)
    end
    return table.concat(r, sep)
end

---@param name string the buffer name to search for
---@return integer | nil buf_id the buffer id
M.getBufferByName = function(name)
    local result = vim.api.nvim_list_bufs()
    for _, buf in pairs(result) do
        if vim.api.nvim_buf_get_name(buf):match(name) then return buf end
    end
    return nil
end

return M
