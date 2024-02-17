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
    for _, file in Utils.pairsByKeys(dir) do
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


---@param db_name string
---Populates the files in the given db's directory
function Files:setup(db_name)
    local parent = Utils.concat({ vim.fn.stdpath("data"), "sqlua", db_name })
    local content = vim.split(
        vim.fn.glob(parent .. "/*"), "\n", { trimempty = true }
    )

    -- iterate through db directory files
    for _, file in Utils.pairsByKeys(content) do
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

function Files:refresh(db_name)
    local old_files = self.files
    self.files = {}
    local f = vim.deepcopy(self)
    f:setup(db_name)
    local new_files = f.files
    self.files = vim.tbl_deep_extend("keep", old_files, new_files)
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
