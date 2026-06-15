-- Hint: use `:h <option>` to figure out the meaning if needed
vim.opt.clipboard = 'unnamedplus'   -- use system clipboard 
vim.opt.completeopt = {'menu', 'menuone', 'noselect'}
vim.opt.mouse = 'a'                 -- allow the mouse to be used in nvim

-- Tab
vim.opt.tabstop = 4                 -- number of visual spaces per TAB
vim.opt.softtabstop = 4             -- number of spaces in tab when editing
vim.opt.shiftwidth = 4              -- insert 4 spaces on a tab
vim.opt.expandtab = true            -- tabs are spaces, mainly because of Python

-- UI config
vim.opt.title = true                -- show a title
vim.opt.titlestring = "%{getcwd()}/%f"
vim.opt.number = true               -- show absolute number
vim.opt.relativenumber = true       -- add numbers to each line on the left side
vim.opt.cursorline = true           -- highlight cursor line underneath the cursor horizontally
vim.opt.splitbelow = true           -- open new vertical split bottom
vim.opt.splitright = true           -- open new horizontal splits right
-- vim.opt.termguicolors = true     -- enable 24-bit RGB color in the TUI
vim.opt.showmode = true             -- we are experienced, wo don't need the "-- INSERT --" mode hint

-- Line and wordbreaks
vim.opt.wrap = true               -- Zeilenumbruch aktivieren
vim.opt.linebreak = true          -- Nur bei ganzen Wörtern umbrechen
vim.opt.breakindent = true        -- Einrückung bei umgebrochenen Zeilen beibehalten
--vim.opt.showbreak = '↪ '          -- Symbol für umgebrochene Zeilen (optional)
vim.opt.textwidth = 0             -- Keine feste Zeilenlänge erzwingen
vim.opt.wrapmargin = 0            -- Kein zusätzlicher Rand für Umbruch
vim.opt.formatoptions:append('l') -- Erzwingt Umbruch bei ganzen Wörtern

-- Searching
vim.opt.incsearch = true            -- search as characters are entered
vim.opt.hlsearch = true             -- do not highlight matches
vim.opt.ignorecase = true           -- ignore case in searches by default
vim.opt.smartcase = true            -- but make it case sensitive if an uppercase is entered
