local M = {}


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


local sep = (function()
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


---@param path_components string[]
---@return string
function M.concat(path_components)
    return table.concat(path_components, sep)
end


M.shallowcopy = function(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

M.splitString = function(str, sep)
  local sep = sep
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for s in string.gmatch(str, "([^"..sep.."]+)") do
    table.insert(t, s)
  end
  return t
end

M.inArray = function(arr, element)
  for _, value in ipairs(arr) do
    if value == element then
      return true
    end
  end
  return false
end

M.removeDuplicates = function(arr)
  local newArray = {}
  for _, element in ipairs(arr) do
    if not M.inArray(newArray, element) then
      table.insert(newArray, element)
    end
  end
  return newArray
end

M.deepReplace = function(table, search_for, replacement)
  if not table then return end
  for key, value in pairs(table) do
    if type(value) == 'table' then
      M.deep_replace(value, search_for, replacement)
    else
      table[key] = value:gsub(search_for, replacement)
    end
  end
end

M.removeEndWhitespace = function(line)
  return line:gsub("^%s*(.-)%s*$", "%1")
end

M.getDatabases = function(file)
  local content = vim.fn.readfile(file)
  content = vim.fn.json_decode(vim.fn.join(content, "\n"))
  return content
end

M.replaceIcons = function(val)
end
-- local parseUrl = function(url)
--   local db = string.gsub(
--     string.sub(url, string.find(url, "%w+:")),
--     "[:]", ""
--   )
--   local username = string.gsub(
--     string.sub(url, string.find(url, "//%w+:")),
--     "[/:]", ""
--   )
--   local password = string.gsub(
--     string.sub(url, string.find(url, ":[%w!@#%$%%%^&%*%(%)%-_=%+]+@")),
--     "[:@]", ""
--   )
--   local server = string.gsub(
--     string.sub(url, string.find(url, "@.+/")),
--     "[@/]", ""
--   )
--   local ip = ""
--   local port = ""
--   if server == "localhost" then
--     ip = "127.0.0.1"
--     port = "5432"
--   else
--     ip = string.sub(server, string.find(server, "+[:/]"))
--     port = string.sub(server, string.find(server, ":+"))
--   end
--   return {
--     db = db,
--     username = username,
--     password = password,
--     server = server,
--     ip = ip,
--     port = port
--   }
-- end

return M
