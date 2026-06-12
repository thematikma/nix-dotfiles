vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'markdown', 'text', 'tex', 'gitcommit' },
  callback = function()
    vim.opt_local.spell = true
    vim.opt_local.spelllang = 'de,en,nb'
  end,
})
