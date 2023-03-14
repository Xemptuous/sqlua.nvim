# sqlua.nvim

A Modern SQL UI for NeoVim written in Lua emphasizing speed and simplicity, turning NeoVim into a full-fledged SQL IDE.

## Installation

### Lazy

```lua
{
    'xemptuous/sqlua.nvim',
    lazy = true,
    event = 'SQLua',
    config = function() require('sqlua').setup(opts) end
}
```
### vim-plug

```lua
Plug 'xemptuous/sqlua.nvim'
```

### Packer
```lua
use "xemptuous/sqlua.nvim"
```

## Setup 

To use, require the setup:
`:lua require('sqlua').setup(opts)`

After the first time running the setup() function, a folder for SQLua will be created in the neovim data directory (~/.local/share/nvim/sqlua/)

The `connections.json` file here will contain your DB URL's, as well as friendly names to call them by.

You can override the default settings by feeding the table as a table to the setup() function:
```lua
{
    db_save_location = "~/.local/share/nvim/sqlua/dbs",
    connections_save_location = "~/.local/share/nvim/sqlua/connections.json"
}
```

the `dbs` folder specific to each URL will host tmp queries and saved queries.

## Usage:

Current commands include:
```
SQLua <dbname> - launches the SQLua UI
SQLuaAddConnection - prompts the user to add a connection to the connections file
```

The sidebar navigator can be used to explore the DB and its various schema and tables, as well as creating various template queries.

### Executing Queries
The editor buffer(s) are used to run queries.

By default, the keymap to execute commands is set to `<leader>r`, acting differently based on mode:

<pre>
    <kdb><leader>-r ('n' mode)</kbd> Runs the entire buffer as a query.
    <kdb><leader>-r ('v', '^V', 'V' mode)</kbd> Runs the selected lines as a query.
</pre>

Upon executing a query, the results will be shown in a results buffer.

## Roadmap

This project is actively being developed, and will hopefully serve as NeoVim's full-fledged SQL IDE moving forward, eliminating the need for long load times and vim extensions.

# TODO: compare SQLua startup time to other IDEs (like DBeaver)

- [x] Create functional connection for psql
- [x] Be able to execute queries from buffer
- [x] Create a minimal UI structure
- [x] Make a functional NvimTree-sidebar for navigating the DB
- [ ] Create db-specific sql files to be stored in sqlua/dbs/<dbname> folder
- [ ] Add an option for "fancier" results pane output
- [ ] Implement syntax highlighting for dbout similar to other SQL IDE's (datetime, numbers, strings, null, etc.)
- [ ] Integrate other databases
- [ ] Implement multiple db's available in sidebar at once (easily jumping between them)
- [ ] Include fancy ui functionality to make SQLua sexy
- [ ] Implement tmp queries, ddl, saved sql files (db specific), and other template queries into the sidebar tree.

