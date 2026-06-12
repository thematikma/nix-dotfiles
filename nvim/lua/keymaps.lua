-- define common options
local opts = {
    noremap = true,      -- non-recursive
    silent = true,       -- do not show message
}

-----------------
-- Normal mode --
-----------------

-- Hint: see `:h vim.map.set()`
-- Better window navigation
vim.keymap.set('n', '<C-h>', '<C-w>h', opts)
vim.keymap.set('n', '<C-j>', '<C-w>j', opts)
vim.keymap.set('n', '<C-k>', '<C-w>k', opts)
vim.keymap.set('n', '<C-l>', '<C-w>l', opts)

-- Resize with arrows
-- delta: 2 lines
vim.keymap.set('n', '<C-Up>', ':resize -2<CR>', opts)
vim.keymap.set('n', '<C-Down>', ':resize +2<CR>', opts)
vim.keymap.set('n', '<C-Left>', ':vertical resize -2<CR>', opts)
vim.keymap.set('n', '<C-Right>', ':vertical resize +2<CR>', opts)

-----------------
-- Visual mode --
-----------------

-- Hint: start visual mode with the same area as the previous area and the same mode
vim.keymap.set('v', '<', '<gv', opts)
vim.keymap.set('v', '>', '>gv', opts)

-- Add a leader key
vim.g.mapleader = ' '  -- Leertaste als Leader
-- Add language spell switching --
--
vim.keymap.set('n', '<leader>sl', function()
  local langs = { 'de', 'en', 'nb' }  -- Deutsch, Englisch, Norwegisch (Bokmål)
  local current = vim.opt.spelllang:get()[1] or 'de'

  -- Finde den Index der aktuellen Sprache
  local current_index = nil
  for i, lang in ipairs(langs) do
    if lang == current then
      current_index = i
      break
    end
  end

  -- Setze die nächste Sprache (oder die erste, wenn am Ende)
  local next_index = (current_index and current_index % #langs) + 1 or 1
  local next_lang = langs[next_index]

  -- Aktiviere die neue Sprache
  vim.opt.spelllang = next_lang
  print("Spell language set to: " .. next_lang)
end, { desc = 'Toggle spell language' })
-- End 
