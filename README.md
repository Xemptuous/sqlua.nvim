# sqlua.nvim
A sql-ui for NeoVim written in Lua inspired by vim-dadbob-ui

### `CURRENTLY A WIP`
i.e., infantile stage

Main goals are to combine vim-dadbod and vim-dadbod-ui.

vim-dadbod is written in vimscript, and is not the cleanest of codebases to contribute to.

vim-dadbod-ui also suffers from vimscript, and can also use a lua update.

## Progress

currently building the barebones; will implement branches of release versions, changelog, and updated README as the project unfolds.

To use, require the setup:
`:lua require('sqlua').setup()`

or include with your favorite package manager.

Current commands include:
```
SQLua - main testing method
SQLuaAddConnection - adds the connection to a local file
```

A folder is created in the stdpath('data') to contain necessary files and dirs.
`~/.local/share/nvim/sqlua/`

A `connections.json` file will serve as the storage location for all URL's (unencrypted) with their associated names.

A folder for `dbs` will be present, hosting tmp files and saved queries for the specific db.

Currently only working on getting postgresql working (will include all in the future), with barebones query output.

## Future Goals

* create a nvim-tree sidebar similar to vim-dadbod-ui
* include a syntax-highlighted query window to color datatypes based on column dtype
* run queries through visual selection (similar to DBeaver and other SQL-IDE's)
* incorporate more modern vim.ui interfaces for that sleek and sexy style
