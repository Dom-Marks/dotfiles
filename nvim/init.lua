-- =====================================================================
--  Beginner-friendly Neovim config
--  Tip: press <Space> and wait - a popup shows available shortcuts.
-- =====================================================================

-- Use gcc (scoop's mingw) to compile Treesitter parsers instead of MSVC
if vim.fn.executable("gcc") == 0 then
  vim.env.PATH = vim.fn.expand("~/scoop/apps/mingw/current/bin") .. ";" .. vim.env.PATH
end
vim.env.CC = "gcc"

-- Leader key (used as a prefix for custom shortcuts)
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- ---------------------------------------------------------------------
-- Basic options
-- ---------------------------------------------------------------------
local opt = vim.opt
opt.number = true          -- line numbers
opt.relativenumber = false -- set to true once you're comfortable with jumps like 5j
opt.mouse = "a"            -- mouse works everywhere
opt.clipboard = "unnamedplus" -- share clipboard with Windows
opt.tabstop = 4
opt.shiftwidth = 4
opt.expandtab = true       -- spaces instead of tabs
opt.smartindent = true
opt.ignorecase = true      -- case-insensitive search...
opt.smartcase = true       -- ...unless you type a capital
-- Use the terminal's own colour palette (Herdr / Windows Terminal theme)
-- instead of Neovim picking its own colours.
opt.termguicolors = false
opt.signcolumn = "yes"
opt.cursorline = true
opt.scrolloff = 8
opt.splitright = true
opt.splitbelow = true
opt.undofile = true        -- undo history survives restarts
opt.updatetime = 250
opt.wrap = false

-- ---------------------------------------------------------------------
-- Handy keymaps
-- ---------------------------------------------------------------------
local map = vim.keymap.set
map("n", "<leader>w", "<cmd>w<cr>", { desc = "Save file" })
map("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit window" })
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })
-- Switching between open files ("tabs" in the top bar)
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next tab" })
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous tab" })
map("n", "<leader>bd", function() Snacks.bufdelete() end, { desc = "Close tab" })
map("n", "<leader>bo", function() Snacks.bufdelete.other() end, { desc = "Close other tabs" })
for i = 1, 9 do
  map("n", "<leader>" .. i, "<cmd>LualineBuffersJump " .. i .. "<cr>", { desc = "Go to tab " .. i })
end

map("n", "<leader>r", "<cmd>w<cr><cmd>split | terminal python %<cr>", { desc = "Run current Python file" })

-- Colours: built-in scheme using the terminal's 16 ANSI colours, and
-- no background fill so the terminal's background shows through.
vim.cmd.colorscheme("default")
for _, g in ipairs({ "Normal", "NormalNC", "SignColumn", "EndOfBuffer" }) do
  vim.api.nvim_set_hl(0, g, { ctermbg = "NONE", bg = "NONE" })
end

-- Diagnostics (errors/warnings) shown inline
vim.diagnostic.config({ virtual_text = true, severity_sort = true, float = { border = "rounded" } })
map("n", "<leader>e", vim.diagnostic.open_float, { desc = "Show error under cursor" })

-- ---------------------------------------------------------------------
-- Plugin manager: lazy.nvim (installs itself on first launch)
-- ---------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- Start screen (dashboard) + utilities from folke/snacks.nvim
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {
      bufdelete = { enabled = true }, -- close buffers without messing up window layout
      dashboard = {
        enabled = true,
        preset = {
          keys = {
            { icon = " ", key = "f", desc = "Find file", action = ":Telescope find_files" },
            { icon = " ", key = "n", desc = "New file", action = ":ene | startinsert" },
            { icon = " ", key = "g", desc = "Search text", action = ":Telescope live_grep" },
            { icon = " ", key = "r", desc = "Recent files", action = ":Telescope oldfiles" },
            { icon = " ", key = "e", desc = "File tree", action = ":Neotree toggle" },
            { icon = " ", key = "c", desc = "Edit config", action = ":e $MYVIMRC" },
            { icon = "󰒲 ", key = "l", desc = "Plugins (Lazy)", action = ":Lazy" },
            { icon = " ", key = "q", desc = "Quit", action = ":qa" },
          },
        },
        sections = {
          { section = "header" },
          { section = "keys", gap = 1, padding = 1 },
          { icon = " ", title = "Recent Files", section = "recent_files", indent = 2, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },

  -- Shows keybinding hints when you press <Space> (great for learning)
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Syntax highlighting (Treesitter)
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      require("nvim-treesitter").install({
        "python", "lua", "vim", "vimdoc", "markdown", "json", "yaml", "toml", "bash",
      })
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          if pcall(vim.treesitter.start, args.buf) then
            vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
          end
        end,
      })
    end,
  },

  -- LSP: language servers for code intelligence (installed into your user folder by Mason)
  { "mason-org/mason.nvim", opts = {} },
  {
    "mason-org/mason-lspconfig.nvim",
    dependencies = { "mason-org/mason.nvim", "neovim/nvim-lspconfig" },
    opts = {
      ensure_installed = { "basedpyright", "ruff", "lua_ls" },
    },
  },

  -- Autocompletion
  {
    "saghen/blink.cmp",
    version = "1.*",
    opts = {
      keymap = { preset = "enter" }, -- <Enter> accepts, <Tab>/<S-Tab> or arrows to move
      completion = { documentation = { auto_show = true } },
      signature = { enabled = true },
      sources = { default = { "lsp", "path", "buffer" } },
    },
  },

  -- Fuzzy finder (find files, search text)
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = "Telescope", -- also load when :Telescope is run (e.g. from the dashboard)
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Search text in project" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Open buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Search help" },
    },
  },

  -- File explorer sidebar
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
    cmd = "Neotree",
    keys = { { "<leader>t", "<cmd>Neotree toggle<cr>", desc = "Toggle file tree" } },
    opts = {},
  },

  -- Nice-to-haves
  -- Status line (bottom) + open files shown as "tabs" (top)
  {
    "nvim-lualine/lualine.nvim",
    opts = {
      options = { theme = "16color", disabled_filetypes = { "snacks_dashboard" } },
      tabline = {
        lualine_a = { { "buffers", mode = 2, symbols = { alternate_file = "" } } }, -- mode 2 = number + name
        lualine_z = { "tabs" },
      },
    },
  },
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },                 -- auto-close brackets
  { "lewis6991/gitsigns.nvim", opts = {} },                                       -- git changes in gutter
}, {
  rocks = { enabled = false },
  change_detection = { notify = false },
})

-- ---------------------------------------------------------------------
-- LSP keymaps (active when a language server is attached)
-- ---------------------------------------------------------------------
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local o = function(desc) return { buffer = args.buf, desc = desc } end
    map("n", "gd", vim.lsp.buf.definition, o("Go to definition"))
    map("n", "K", vim.lsp.buf.hover, o("Show documentation"))
    map("n", "<leader>rn", vim.lsp.buf.rename, o("Rename symbol"))
    map("n", "<leader>ca", vim.lsp.buf.code_action, o("Code action / quick fix"))
    map("n", "<leader>cf", function() vim.lsp.buf.format() end, o("Format file"))
  end,
})

vim.lsp.config("lua_ls", { settings = { Lua = { diagnostics = { globals = { "vim" } } } } })
