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


local function recursiveRefresh(of, nf)
    for fname, file in pairs(nf.files) do
        if of.files[fname] ~= nil and nf.files[fname] == nil then
            nf.files[fname] = file
        elseif of.files[fname] == nil and nf.files[fname] ~= nil then
            of.files[fname] = file
        end
        nf.files[fname].expanded = of.files[fname].expanded
        if next(nf.files) ~= nil then
            recursiveRefresh(of.files[fname], nf.files[fname])
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
    local old_files = nil
    if next(self.files) ~= nil then
        old_files = vim.deepcopy(self.files)
    end
    self.db_name = db_name
    self.files = {}

    -- iterate through db directory files
    for _, file in Utils.pairsByKeys(content) do
        local f = vim.deepcopy(File)
        local fname = Utils.getFileName(file)

        table.insert(f.parents, db_name)
        if vim.fn.isdirectory(file) == 1 then
            f.name = fname
            f.isdir = true
            f.expanded = false
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
            f.expanded = false
            f.path = Utils.concat({
                vim.fn.stdpath("data"), "sqlua", f.parents, f.name
            })
            self.files[fname] = f
        end
    end
    if old_files ~= nil then
        for fname, file in pairs(self.files) do
            if old_files[fname] ~= nil and self.files[fname] == nil then
                self.files[fname] = file
            elseif old_files[fname] == nil and self.files[fname] ~= nil then
                old_files[fname] = file
            end
            self.files[fname].expanded = old_files[fname].expanded
            if next(self.files) ~= nil then
                recursiveRefresh(old_files[fname], self.files[fname])
            end
        end
    end

    return self
end


function Files:refresh()
    self:setup(self.db_name)
end


local function recurseFind(table, search)
    for name, file in pairs(table) do
        if name == search then
            return file
        elseif file.isdir then
            local found = recurseFind(file.files, search)
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
                local found = recurseFind(file.files, search)
                if found ~= nil and found.name == search then
                    return found
                end
            end
        end
    end
end


return Files
