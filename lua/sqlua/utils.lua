local M = {}

---@param v table
---@return table v
---prints the content of a given table
P = function(v)
	print(vim.inspect(v))
	return v
end

RELOAD = function(...)
	return require("plenary.reload").reload_module(...)
end

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
    for i = 1, math.floor(#tbl/2), 1 do
        tbl[i], tbl[#tbl-i+1] = tbl[#tbl-i+1], tbl[i]
    end
    return tbl
end

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

---@param orig table
---@return table
---Creates a shallow copy of a given table
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

---@param str string string
---@param separator string delimiter
---@return string[]
---Splits string by given delimiter and returns an array
M.splitString = function(str, separator)
	if separator == nil then
		separator = "%s"
	end
	local t = {}
	for s in string.gmatch(str, "([^" .. separator .. "]+)") do
		table.insert(t, s)
	end
	return t
end

---@param arr table
---@param element any
---@return boolean
---Checks whether the given element is in the top level of the array/table
M.inArray = function(arr, element)
	for _, value in ipairs(arr) do
		if value == element then
			return true
		end
	end
	return false
end

---@param arr table
---@return table
---Returns a new table with duplicate values removed (top level only)
M.removeDuplicates = function(arr)
	local newArray = {}
	for _, element in ipairs(arr) do
		if not M.inArray(newArray, element) then
			table.insert(newArray, element)
		end
	end
	return newArray
end

---@param table table table to begin searching
---@param search_for any what to search for
---@param replacement any value to replace with
---@return nil
M.deepReplace = function(table, search_for, replacement)
	if not table then
		return
	end
	for key, value in pairs(table) do
		if type(value) == "table" then
			M.deep_replace(value, search_for, replacement)
		else
			table[key] = value:gsub(search_for, replacement)
		end
	end
end

---@param line string
---@return string
---Trims leading and trailing whitespace
M.removeEndWhitespace = function(line)
	return line:gsub("^%s*(.-)%s*$", "%1")[1]
end

M.getFileName = function(path)
	return path:match("^.+/(.+)$")
end

---@param file table|string the connections.json file
---@return table content json table object
M.getDatabases = function(file)
	local content = vim.fn.readfile(file)
    if next(content) == nil then
        return {}
    end
	content = vim.fn.json_decode(vim.fn.join(content, "\n"))
	return content
end

---@param t table
---@return iterator
---replaces pairs() by utilizing a sorted table
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

return M
