-- Neovim version gates: version-sensitive plugins are only registered when the
-- running Neovim satisfies their minimum requirement, so this single config
-- works on both old and new Neovim (older versions get a reduced feature set).
-- 版本基准（2026-08）: brew 0.12.4 / apt 0.11.6 / extra 0.12.4，最低 0.11.6
local has_nvim_010 = vim.fn.has("nvim-0.10") == 1
local has_nvim_011 = vim.fn.has("nvim-0.11") == 1
local has_nvim_012 = vim.fn.has("nvim-0.12") == 1

-- Bootstrap lazy.nvim (Plugin Manager)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
local uv = vim.uv or vim.loop
if not uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.notify("Failed to clone lazy.nvim. Check network access and rerun Neovim.", vim.log.levels.ERROR)
    return
  end
end
vim.opt.rtp:prepend(lazypath)

-- Base Settings
vim.g.mapleader = ","
vim.g.maplocalleader = ","

-- 启用文件类型检测与插件/缩进（各文件类型插件依赖此设置）
vim.cmd("filetype plugin indent on")

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

-- Undo Settings & Keymaps
vim.opt.undofile = false -- 设置为 true 启用持久化撤销（Neovim 会自动管理并创建撤销目录）
vim.opt.undolevels = 10000
vim.opt.undoreload = 10000

-- 插入模式下的撤销断点（按标点符号分段撤销，避免一次性撤销太多）
vim.keymap.set("i", ",", ",<C-g>u")
vim.keymap.set("i", ".", ".<C-g>u")
vim.keymap.set("i", "!", "!<C-g>u")
vim.keymap.set("i", "?", "?<C-g>u")
vim.keymap.set("i", ";", ";<C-g>u")

-- Plugins Configuration
-- 按 Neovim 版本门控动态构建插件列表，兼容旧版与新版。
local plugins = {
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

  -- Git
  { "lewis6991/gitsigns.nvim", config = true },
  { "tpope/vim-fugitive" },

  -- Utilities (Editing enhancements matching vimrc)
  { "tpope/vim-surround" },
  { "tpope/vim-repeat" },
  { "numToStr/Comment.nvim", config = true }, -- gcc / gc
  { "tpope/vim-sleuth" }, -- auto indent
  { "windwp/nvim-autopairs", config = true }, -- auto close brackets
  { "mbbill/undotree", keys = { { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Toggle UndoTree" } } },

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
  },
}

-- LSP / Formatting (requires Neovim 0.11+)
if has_nvim_011 then
  vim.list_extend(plugins, {
    { "williamboman/mason.nvim", config = true },
    { "williamboman/mason-lspconfig.nvim", config = function()
        require("mason-lspconfig").setup({
            -- clangd is resolved directly from PATH.
            ensure_installed = { "pyright", "rust_analyzer", "ts_ls", "bashls" }
        })
    end },
    { "neovim/nvim-lspconfig", config = function()
        local servers = { "pyright", "rust_analyzer", "ts_ls", "bashls", "clangd" }
        local capabilities = require("cmp_nvim_lsp").default_capabilities()
        for _, server in ipairs(servers) do
          vim.lsp.config(server, { capabilities = capabilities })
        end
        vim.lsp.enable(servers)
        -- Keymaps
        vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {desc="Go to definition"})
        vim.keymap.set('n', 'K', vim.lsp.buf.hover, {desc="Hover info"})
        vim.keymap.set('n', '<leader>r', vim.lsp.buf.rename, {desc="Rename symbol"})
        vim.keymap.set('n', '<leader>a', vim.lsp.buf.code_action, {desc="Code action"})
    end },
    { "stevearc/conform.nvim",
      cmd = { "ConformInfo" },
      keys = {
        {
          "<leader>f",
          function()
            require("conform").format({ async = true, lsp_fallback = false })
          end,
          desc = "Format buffer",
        },
      },
      config = function()
        require("conform").setup({
          -- Formatters are resolved from PATH.
          formatters_by_ft = {
            lua = { "stylua" },
            python = { "ruff_format" },
            rust = { "rustfmt" },
            javascript = { "biome" },
            javascriptreact = { "biome" },
            typescript = { "biome" },
            typescriptreact = { "biome" },
            json = { "biome" },
            jsonc = { "biome" },
            sh = { "shfmt" },
            c = { "clang-format" },
            cpp = { "clang-format" },
          },
          format_on_save = nil,
        })
      end
    },
  })
end

-- Syntax Highlighting
-- 0.12+ 使用重写后的 main API；0.10-0.11 固定使用兼容旧 API 的 v0.10.0。
if has_nvim_012 then
  vim.list_extend(plugins, {
    {
      "nvim-treesitter/nvim-treesitter",
      lazy = false,
      build = ":TSUpdate",
      config = function()
        local treesitter = require("nvim-treesitter")
        local parsers = { "c", "lua", "vim", "vimdoc", "query", "rust", "python" }

        treesitter.setup({
          install_dir = vim.fn.stdpath("data") .. "/site",
        })
        treesitter.install(parsers):wait(300000)

        vim.api.nvim_create_autocmd("FileType", {
          desc = "Enable Treesitter highlighting when a parser is available",
          callback = function(args)
            pcall(vim.treesitter.start, args.buf)
          end,
        })
      end,
    },
  })
elseif has_nvim_010 then
  vim.list_extend(plugins, {
    {
      "nvim-treesitter/nvim-treesitter",
      tag = "v0.10.0",
      build = ":TSUpdate",
      config = function()
        require("nvim-treesitter.configs").setup({
          ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "rust", "python" },
          auto_install = true,
          highlight = { enable = true },
        })
      end,
    },
  })
end

-- Git UI: neogit（要求 Neovim 0.10+）
-- lazygit（外部 TUI）独立于 neogit，两者入口不冲突。
if has_nvim_010 then
  vim.list_extend(plugins, {
    { "NeogitOrg/neogit",
      config = function() require("neogit").setup({}) end,
      keys = { { "<leader>gi", "<cmd>Neogit<CR>", desc = "Neogit (git interface)" } } },
  })
end

require("lazy").setup(plugins)

-- lazygit（外部 TUI，检测到可执行文件时启用）
if vim.fn.executable("lazygit") == 1 then
  vim.keymap.set("n", "<leader>gg", function()
    vim.cmd("terminal lazygit")
  end, { desc = "Open lazygit" })
end
