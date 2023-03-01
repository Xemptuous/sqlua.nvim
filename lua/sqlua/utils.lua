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


return M
