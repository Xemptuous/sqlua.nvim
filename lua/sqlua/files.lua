local Utils = require("sqlua.utils")
local Files = {
    files = {}
}

local File = {
    name = "",
    path = "",
    isdir = false,
    expanded = false,
    parents = {},
    files = {},
}


local function iterateFiles(dir, parent)
    for _, file in pairs(dir) do
        local f = vim.deepcopy(File)
        local fname = Utils.getFileName(file)
        f.parents = vim.deepcopy(parent.parents)

        table.insert(f.parents, parent.name)
        if vim.fn.isdirectory(file) == 1 then
            f.name = fname
            f.isdir = true
            f.path = Utils.concat({
                vim.fn.stdpath("data"), "sqlua", f.parents, f.name
            })
            parent.files[fname] = f
            dir = vim.split(
                vim.fn.glob(file .. "/*"), "\n", {
                    trimempty = true
                }
            )
            iterateFiles(dir, f)
        else
            f.name = fname
            f.path = Utils.concat({
                vim.fn.stdpath("data"), "sqlua", f.parents, f.name
            })
            parent.files[f.name] = f
        end
    end
end


function Files:refresh()
end


---@param db_name string
function Files:setup(db_name)
    -- reset files
    if next(self.files) ~= nil then
        self.files = {}
    end
    local parent = Utils.concat({ vim.fn.stdpath("data"), "sqlua", db_name })
    local content = vim.split(
        vim.fn.glob(parent .. "/*"), "\n", { trimempty = true }
    )

    -- iterate through db directory files
    for _, file in pairs(content) do
        local f = vim.deepcopy(File)
        local fname = Utils.getFileName(file)

        table.insert(f.parents, db_name)
        if vim.fn.isdirectory(file) == 1 then
            f.name = fname
            f.isdir = true
            f.path = Utils.concat({
                vim.fn.stdpath("data"), "sqlua", f.parents, f.name
            })
            self.files[fname] = f
            local dir = vim.split(
                vim.fn.glob(file .. "/*"), "\n", { trimempty = true }
            )
            iterateFiles(dir, f)
        else
            f.name = fname
            f.isdir = false
            f.path = Utils.concat({
                vim.fn.stdpath("data"), "sqlua", f.parents, f.name
            })
            self.files[fname] = f
        end
    end
    return self
end

local function recurse(table, search)
    for name, file in pairs(table) do
        if name == search then
            return file
        elseif file.isdir then
            local found = recurse(file.files, search)
            if found ~= nil and found.name == search then
                return found
            end
        end
    end
end

function Files:find(search)
    for name, file in pairs(self.files) do
        if name == search then
            return file
        elseif file.isdir then
            if next(file.files) ~= nil then
                local found = recurse(file.files, search)
                if found ~= nil and found.name == search then
                    return found
                end
            end
        end
    end
end



return Files
