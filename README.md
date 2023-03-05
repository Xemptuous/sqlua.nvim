# sqlua.nvim

A Modern SQL UI for NeoVim written in Lua emphasizing speed and simplicity, turning NeoVim into a full-fledged SQL IDE.

## Quickstart

To use, require the setup:
`:lua require('sqlua').setup(opts)`

or include with your favorite package manager.

lazy.nvim

```lua
{
    'xemptuous/sqlua.nvim',
    event = 'SQLua',
    config = function() require('sqlua').setup(opts) end
}
```

Current options include:
```lua
{
    db_save_location = "~/.local/share/nvim/sqlua/dbs",
    connections_save_location = "~/.local/share/nvim/sqlua/connections.json"
}
```

Current commands include:
```
SQLua <dbname> - launches the SQLua UI
SQLuaAddConnection - adds the connection to a local file (url + db name)
```

A folder is created in the stdpath('data') to contain necessary files and dirs.
`~/.local/share/nvim/sqlua/`

A `connections.json` file will serve as the storage location for all URL's (unencrypted) with their associated names.

A folder for `dbs` will be present, hosting tmp files and saved queries for the specific db.

Upon launching the `SQLua <dbname>` command, the UI will be launched, including an editor and a database navigator side-bar.

Upon executing the query, a results pane will be created showing the dbout.

## Executing Queries

By default, the keymap to execute commands is set to `<leader>r`, acting differently based on mode:

> Normal Mode: the entire buffer will be executed

> Visual Mode: the selection will be executed.

## Roadmap

- [x] Create functional connection for psql
- [x] Be able to execute queries from buffer
- [x] Create a minimal UI structure
- [ ] Make a functional NvimTree-sidebar for navigating the DB
- [ ] Create db-specific sql files to be stored in sqlua/dbs/<dbname> folder
- [ ] Add an option for "fancier" results pane output
- [ ] Implement syntax highlighting for dbout similar to other SQL IDE's (datetime, numbers, strings, null, etc.)
- [ ] Integrate other databases
- [ ] Implement multiple db's available in sidebar at once (easily jumping between them)
- [ ] Include fancy ui functionality to make SQLua sexy
