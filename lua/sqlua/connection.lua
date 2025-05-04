local utils = require("sqlua.utils")

---@class Connections
local Connections = {}

--- Default names and pointers to specific connector objects.
--- Key is name found in jbdc url (except for some specifics like Snowflake)
local Cons = {
    snowflake = require("sqlua.connectors.snowflake"),
    mariadb = require("sqlua.connectors.mariadb"),
    mysql = require("sqlua.connectors.mysql"),
    postgres = require("sqlua.connectors.postgres"),
    postgresql = require("sqlua.connectors.postgres"),
    sqlite = require("sqlua.connectors.sqlite"),
}

--- Base setup class for specific dbms
---@param name string name of the specific connection
---@param url string jdbc url for the con
---@return nil
Connections.setup = function(name, url, options)
    --- get dbms name from jdbc url
    local s = url:find("://") or #url + 1
    local dbms = url:sub(0, s - 1)
    -- TODO: clean this up for future additions to be cleaner/simpler
    if dbms == url then
        if dbms ~= "snowflake" then
            local con = Cons.sqlite
            return con:setup(name, url, options)
        end
    end
    local con = Cons[dbms]
    return con:setup(name, url, options)
end

CONNECTIONS_FILE = utils.concat({
    vim.fn.stdpath("data"),
    "sqlua",
    "connections.json",
})

---Reads the connection.json file and returns content as a table
---@return table<string, string>
Connections.read = function()
    local content = vim.fn.readfile(CONNECTIONS_FILE)
    content = vim.fn.json_decode(vim.fn.join(content, "\n"))
    return content
end

---Writes the given table to the connections.json file.
---table is expected to be in json format
---@param data table<string, string>
---@return nil
Connections.write = function(data)
    local json = vim.fn.json_encode(data)
    vim.fn.writefile({ json }, CONNECTIONS_FILE)
end

---Adds the given url + name to the connections.json file
---@param url string
---@param name string
---@return nil
Connections.add = function(url, name)
    local file = Connections.read()
    table.insert(file, { url = url, name = name })
    vim.fn.mkdir(SQLUA_ROOT_DIR .. "/" .. name, "p")
    Connections.write(file)
end

return Connections
