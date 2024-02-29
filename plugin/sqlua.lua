if vim.g.loaded_sqlua then
    return
end

vim.g.loaded_sqlua = true

vim.cmd('command! SQLua lua require("sqlua").setup()')
