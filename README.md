# 🛢️ SQLua.nvim

A Modern SQL UI for NeoVim written in Lua emphasizing speed and simplicity, turning NeoVim into a full-fledged SQL IDE.

![SQLua](img/sqlua_example.png)

Currently supported DBMS:
* SnowFlake
* PostgreSQL
* MySQL
* MariaDB
* SQLite

## Installation

### Lazy

```lua
{
    'xemptuous/sqlua.nvim',
    lazy = true,
    cmd = 'SQLua',
    config = function() require('sqlua').setup() end
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

To launch SQLua quickly, consider adding an alias to your shell config
```
alias nvsql="nvim '+SQLua'"
```

## Requirements

Neovim 0.10.0+

Based on the DBMS' used, different cli tools will be required. 

* `PostgreSQL`: psql
* `MariaDB`: mariadb
* `MySQL`: mysql
* `Snowflake`: snowsql
* `SQLite`: sqlite3

## Setup

The `connections.json` file is an array of json objects contains all connection information. The required keys are `name` and `url`.

Specific formatting is required for certain databases. Here are some samples of entries for `connections.json` based on dbms:

<details>
  <summary><strong>PostgreSQL</strong></summary>

  ```json
  {
      "name": "mydb",
      "url": "postgres://admin:pass@localhost:5432/mydb"
  }
  ```

</details>
<details>
  <summary><strong>MariaDB</strong></summary>

  ```json
  {
      "name": "mydb",
      "url": "mariadb://admin:pass@localhost:5432/mydb"
  }
  ```
</details>
<details>
  <summary><strong>MySQL</strong></summary>

  ```json
  {
      "name": "mydb",
      "url": "mysql://admin:pass@localhost:5432/mydb"
  }
  ```
</details>
<details>
  <summary><strong>Snowflake</strong></summary>

  >  snowsql client will handle all connections 

  ```json
  {
      "name": "mydb",
      "url": "snowflake"
  }
  ```
</details>
<details>
  <summary><strong>SQLite</strong></summary>

  ```json
  {
      "name": "mydb",
      "url": "/path/to/database/file.db"
  }
  ```
</details>

## Default Config

You can override the default settings by feeding the table as a table to the setup() function:
```lua
{
    -- the parent folder that databases will be placed, holding
    -- various tmp files and other saved queries.
    db_save_location = "~/.local/share/nvim/sqlua/",
    -- where to save the json config containing connection information
    connections_save_location = "~/.local/share/nvim/sqlua/connections.json"
    -- the default limit attached to queries
    -- currently only works on "Data" command under a table
    default_limit = 200,
    -- whether to introspect the database on SQLua open or when first expanded
    -- through the sidebar
    load_connections_on_start = false,
    keybinds = {
        execute_query = "<leader>r",
        activate_db = "<C-a>",

        -- Execute query (just like keybinds.execute_query) while in insert mode for query
        insert_execute_query = "<C-r>",
    }
}
```
---
## Usage:

Open SQLua with the command `:SQLua`

Edit connections with `:SQLuaEdit`

### Executing Queries
Queries run in the editor buffers will use the currently active db, which will be highlighted on the sidebar. The desired connection
can be set to "active" using the `activate_db` keybind, normally <kbd>Ctrl</kbd>+<kbd>a</kbd>

By default, the keymap to execute commands is set to `<leader>r`, acting differently based on mode:

<pre>
    <kdb>&lt;leader>r</kbd> (normal mode): Runs the entire buffer as a query.
    <kdb>&lt;leader>r</kbd> (visual mode): Runs the selected lines as a query. (visual, visual block, and/or visual line)
</pre>

You can also execute a query while editing it (default: `<C-r>`).

Upon executing a query, the results will be shown in a results buffer.

Note: template DDL statements do not need to set the active DB; i.e., they will always
be run based on the parent table, schema, and database.

### Saved Files
Each database will have a `Queries` folder which corresponds to the directory named after the connection, found in `~/.local/share/nvim/sqlua/`

Files can be added and deleted using <kbd>a</kbd> and <kbd>d</kbd> inside this node of the sidebar tree.

### Quicker Navigation
<kbd>o</kbd> will toggle the fold for the current level, expanding the node under the cursor, or collapsing the direct parent.

<kbd>O</kbd> will collapse the entire database connection in the sidebar.

## Roadmap

This project is actively being developed, and will hopefully serve as NeoVim's full-fledged SQL IDE moving forward, eliminating the need for long load times and multiple vim extensions.

- [x] Create functional connection for psql
- [x] Be able to execute queries from buffer
- [x] Create a minimal UI structure
- [x] Make a functional NvimTree-sidebar for navigating the DB
- [x] Implement multiple db's available in sidebar at once (easily jumping between them)
- [x] Implement queries, ddl, and other template queries into the sidebar tree.
- [x] Create asynchronous jobs for queries and connections.
- [x] Create db-specific sql files to be stored in sqlua/dbs/<dbname> folder
- [x] Add default limit functionality
- [ ] Implement Nvim-Tree QoL features into sidebar
- [ ] Add DB Inspection + nvim-cmp completions
- [ ] Implement connection sessions and active connections
- [ ] Add an option for "fancier" results pane output
- [ ] Implement syntax highlighting for dbout similar to other SQL IDE's (datetime, numbers, strings, null, etc.)
- [ ] Include fancy ui functionality to make SQLua sexy
