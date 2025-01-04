local utils = require("sqlua.utils")

---@class Connections
local Connections = {}

local Cons = {
    snowflake = require("sqlua.connectors.snowflake"),
    mariadb = require("sqlua.connectors.mariadb"),
    mysql = require("sqlua.connectors.mysql"),
    postgres = require("sqlua.connectors.postgres"),
}

---@param name string
---@param url string
---@return nil
Connections.setup = function(name, url, options)
    local s = url:find("://") or #url + 1
    local dbms = url:sub(0, s - 1)
    local con = Cons[dbms]
    local connection = con:setup(name, url, options)
    return connection
end

CONNECTIONS_FILE = utils.concat({
    vim.fn.stdpath("data"),
    "sqlua",
    "connections.json",
})

---@return table<string, string>
---Reads the connection.json file and returns content as a table
Connections.read = function()
    local content = vim.fn.readfile(CONNECTIONS_FILE)
    content = vim.fn.json_decode(vim.fn.join(content, "\n"))
    return content
end

---@param data table<string, string>
---@return nil
---Writes the given table to the connections.json file.
---table is expected to be in json format
Connections.write = function(data)
    local json = vim.fn.json_encode(data)
    vim.fn.writefile({ json }, CONNECTIONS_FILE)
end

---@param url string
---@param name string
---@return nil
---Adds the given url + name to the connections.json file
Connections.add = function(url, name)
    local file = Connections.read()
    table.insert(file, { url = url, name = name })
    vim.fn.mkdir(SQLUA_ROOT_DIR .. "/" .. name, "p")
    Connections.write(file)
end

return Connections
