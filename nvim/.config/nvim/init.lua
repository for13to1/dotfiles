-- Neovim version check (0.11+ is required for new LSP APIs)
if vim.fn.has("nvim-0.11") == 0 then
  vim.notify("Neovim 0.11+ is required for this configuration!", vim.log.levels.ERROR)
  return
end

-- Bootstrap lazy.nvim (Plugin Manager)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Base Settings
vim.g.mapleader = ","
vim.g.maplocalleader = ","

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.termguicolors = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.scrolloff = 8

-- Tab & Indents
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.autoindent = true

-- System Clipboard
vim.opt.clipboard = "unnamedplus"

-- Plugins Configuration
require("lazy").setup({
  -- UI / Theme
  { "sainnhe/sonokai", lazy = false, priority = 1000, config = function() vim.cmd.colorscheme("sonokai") end },
  { "nvim-lualine/lualine.nvim", dependencies = { "nvim-tree/nvim-web-devicons" }, config = true },

  -- File Explorer
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "nvim-tree/nvim-web-devicons", "MunifTanjim/nui.nvim" },
    keys = { { "<leader>n", "<cmd>Neotree toggle<cr>", desc = "NeoTree" } },
  },

  -- Fuzzy Finder
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<C-p>", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
      { "<C-f>", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
      { "<leader>b", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    },
  },

  -- Syntax Highlighting
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate", config = function()
    require("nvim-treesitter").setup({ ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "rust", "python" }, auto_install = true })
  end },

  -- Git
  { "lewis6991/gitsigns.nvim", config = true },
  { "tpope/vim-fugitive" },

  -- Utilities (Editing enhancements matching vimrc)
  { "tpope/vim-surround" },
  { "tpope/vim-repeat" },
  { "numToStr/Comment.nvim", config = true }, -- gcc / gc
  { "tpope/vim-sleuth" }, -- auto indent
  { "windwp/nvim-autopairs", config = true }, -- auto close brackets

  -- LSP / Autocompletion (Replacing ALE)
  { "williamboman/mason.nvim", config = true },
  { "williamboman/mason-lspconfig.nvim", config = function()
      require("mason-lspconfig").setup({
          ensure_installed = { "pylsp", "rust_analyzer", "ts_ls", "bashls" }
      })
  end },
  { "neovim/nvim-lspconfig", config = function()
      local servers = { "pylsp", "rust_analyzer", "ts_ls", "bashls" }
      for _, server in ipairs(servers) do
        vim.lsp.config(server, {})
      end
      vim.lsp.enable(servers)
      -- Keymaps
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {desc="Go to definition"})
      vim.keymap.set('n', 'K', vim.lsp.buf.hover, {desc="Hover info"})
      vim.keymap.set('n', '<leader>r', vim.lsp.buf.rename, {desc="Rename symbol"})
      vim.keymap.set('n', '<leader>a', vim.lsp.buf.code_action, {desc="Code action"})
  end },

  -- Formatting
  { "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    config = function()
      require("conform").setup({
        formatters_by_ft = {
          lua = { "stylua" },
          python = { "isort", "black" },
          rust = { "rustfmt" },
          javascript = { "prettier" },
          typescript = { "prettier" },
          json = { "prettier" },
          sh = { "shfmt" },
        },
        format_on_save = { timeout_ms = 500, lsp_fallback = true },
      })
    end
  },

  -- Completion
  { "hrsh7th/nvim-cmp",
    dependencies = { "hrsh7th/cmp-nvim-lsp", "hrsh7th/cmp-buffer", "hrsh7th/cmp-path", "saadparwaiz1/cmp_luasnip", "L3MON4D3/LuaSnip" },
    config = function()
      local cmp = require("cmp")
      cmp.setup({
        snippet = { expand = function(args) require('luasnip').lsp_expand(args.body) end },
        mapping = cmp.mapping.preset.insert({
          ['<C-b>'] = cmp.mapping.scroll_docs(-4),
          ['<C-f>'] = cmp.mapping.scroll_docs(4),
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<C-e>'] = cmp.mapping.abort(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item.
          ['<Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_next_item() else fallback() end
          end, { "i", "s" }),
          ['<S-Tab>'] = cmp.mapping(function(fallback)
            if cmp.visible() then cmp.select_prev_item() else fallback() end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' }, { name = 'luasnip' }
        }, { { name = 'buffer' }, { name = 'path' } })
      })
    end
  }
})
