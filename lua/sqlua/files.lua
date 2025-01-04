local Utils = require("sqlua.utils")

--- Main wrapper for all filesystem files for specific connections
---@class Files
local Files = {
    files = {},
}

---@class File
---@field name string full file name
---@field path string absolute path to file
---@field isdir boolean if is dir
---@field expanded boolean if expanded in UI
---@field parents table all parent files for this file
---@field files table all current and children files for this file
local File = {
    name = "",
    path = "",
    isdir = false,
    expanded = false,
    parents = {},
    files = {},
}

---@param parent_path string path to iterate
---@param parent_file File parent File object to update
---@return nil
local function iterateFiles(parent_path, parent_file)
    local uv = vim.uv

    local fs_dir = uv.fs_opendir(parent_path, nil, 1000)
    if fs_dir == nil then return end

    local files = uv.fs_readdir(fs_dir)

    for _, file in pairs(files) do
        local f = vim.deepcopy(File)
        f.name = file.name
        f.path = Utils.concat({ parent_path, file.name })
        f.expanded = false
        f.isdir = file.type == "directory"
        parent_file.files[file.name] = f
    end
end

--- Helper to recursively refresh/update file objects
---@param of table old file
---@param nf table new file
---@return nil
local function recursiveRefresh(of, nf)
    for fname, file in pairs(nf.files) do
        if of.files[fname] ~= nil and nf.files[fname] == nil then
            nf.files[fname] = file
        elseif of.files[fname] == nil and nf.files[fname] ~= nil then
            of.files[fname] = file
        end
        nf.files[fname].expanded = of.files[fname].expanded
        if next(nf.files) ~= nil then recursiveRefresh(of.files[fname], nf.files[fname]) end
    end
end

---Populates files in the given db's directory
---@param db_name string
function Files:setup(db_name)
    local parent = Utils.concat({ vim.fn.stdpath("data"), "sqlua", db_name })

    -- if we already have files, do an update after the initial finds
    local old_files = nil
    if next(self.files) ~= nil then old_files = vim.deepcopy(self.files) end

    self.db_name = db_name
    self.files = {}

    iterateFiles(parent, self)

    -- do updates if not first run
    if old_files ~= nil then
        for fname, file in pairs(self.files) do
            if old_files[fname] ~= nil and self.files[fname] == nil then
                self.files[fname] = file
            elseif old_files[fname] == nil and self.files[fname] ~= nil then
                old_files[fname] = file
            end
            self.files[fname].expanded = old_files[fname].expanded
            if next(self.files) ~= nil then recursiveRefresh(old_files[fname], self.files[fname]) end
        end
    end

    return self
end

--- helper for Files:find()
---@param table table
---@param search string
local function recurseFind(table, search)
    for name, file in pairs(table) do
        if name == search then
            return file
        elseif file.isdir then
            local found = recurseFind(file.files, search)
            if found ~= nil and found.name == search then return found end
        end
    end
end

--- Attempt to find and return the specific file in this db connection dir by name
---@param search string the filename to search for
---@return File | nil
function Files:find(search)
    for name, file in pairs(self.files) do
        if name == search then
            return file
        elseif file.isdir then
            if next(file.files) ~= nil then
                local found = recurseFind(file.files, search)
                if found ~= nil and found.name == search then return found end
            end
        end
    end
end

return Files
