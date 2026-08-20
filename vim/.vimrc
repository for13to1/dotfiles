" =============================================================================
" 版本基准（2026-08）: brew 9.2.0950 / apt 9.1.2141 / extra 9.2.0849，最低 9.1.2141
" =============================================================================

" =============================================================================
" 编码与兼容性
" =============================================================================

set encoding=utf-8
" 按优先级依次尝试：BOM > UTF-8 > GB18030 > Latin1
set fileencodings=ucs-bom,utf-8,gb18030,latin1
set nocompatible                " 关闭 Vi 兼容模式，启用 Vim 全部功能

" =============================================================================
" 文件管理
" =============================================================================

set nobackup                    " 不生成备份文件（filename~）
set noswapfile                  " 不生成交换文件（.filename.swp）
set autoread                    " 文件在 Vim 之外被修改时自动重新读入
set autowrite                   " 切换缓冲区时自动保存
set confirm                     " 处理未保存文件时弹出确认

" 持久化 undo：默认关闭；如需启用，把下面改成 set undofile 即可
set noundofile
if &undofile
    set undodir=~/.vim/undodir
    if !isdirectory(&undodir)
        call mkdir(&undodir, 'p', 0700)
    endif
endif

" 插入模式下的撤销断点（按标点符号分段撤销，避免一次性撤销太多）
inoremap , ,<C-g>u
inoremap . .<C-g>u
inoremap ! !<C-g>u
inoremap ? ?<C-g>u
inoremap ; ;<C-g>u

" =============================================================================
" 搜索
" =============================================================================

set hlsearch                    " 高亮搜索结果
set incsearch                   " 边输入边搜索（实时预览）
set ignorecase                  " 搜索时忽略大小写
set smartcase                   " 但如果输入了大写字母，则精确匹配

" =============================================================================
" 外观
" =============================================================================

syntax enable
set number                      " 显示行号
set cc=100                      " 在第 100 列显示参考线
set cursorline                  " 高亮当前行
set ruler                       " 右下角显示光标位置
set showmatch                   " 输入括号时短暂跳转到匹配的括号
set wildmenu                    " 命令行 Tab 补全时显示候选菜单
set completeopt-=preview        " 补全时不弹出预览窗口

" 终端支持 24-bit 真彩色时启用
if has('termguicolors') && ($COLORTERM == 'truecolor' || $COLORTERM == '24bit')
    set termguicolors
endif

set background=dark
colorscheme retrobox

" =============================================================================
" 缩进
" =============================================================================

filetype on
filetype plugin on
filetype indent on              " 根据文件类型自动缩进

set tabstop=4                   " Tab 显示为 4 个空格宽
set shiftwidth=4                " 自动缩进使用 4 个空格
set softtabstop=4               " 按 Tab 键插入 4 个空格
set expandtab                   " 用空格替代 Tab 字符
set autoindent                  " 新行继承上一行的缩进
set cindent                     " C 语言风格的智能缩进
set smartindent                 " 识别 { } 等结构自动调整缩进

" =============================================================================
" 鼠标
" =============================================================================

if has('mouse')
    if has('gui_running') || (&term =~ 'xterm' && !has('mac'))
        set mouse=a             " GUI 或 xterm 下启用全模式鼠标
    else
        set mouse=nvi           " 终端下仅在 Normal/Visual/Insert 模式启用
    endif
endif

" =============================================================================
" 粘贴模式
" =============================================================================
" Vim 8.0.210+ 已内置 bracketed paste，无需配置

" 防止同一文件被多个 Vim 实例同时编辑（尝试跳转到已打开的实例）
packadd! editexisting

" =============================================================================
" 系统剪贴板（vim 9.1+）
"   1. 原生 +clipboard  → unnamedplus（macOS 自带 vim、Arch vim）
"   2. vim 9.1+         → v:clipproviders + 'clipmethod'（如 Ubuntu vim-nox 的 -clipboard）
"                         + 官方 osc52 包（SSH/远程无显示环境兜底）
" 工具检测顺序对齐 nvim：wl-copy（Wayland）→ xclip（X11）→ pbcopy（macOS）。
" =============================================================================

" 检测可用的系统剪贴板工具，返回 [copy_cmd, paste_cmd]，找不到返回空列表
function! s:DetectClipTool() abort
    if executable('wl-copy') && executable('wl-paste') && !empty($WAYLAND_DISPLAY)
        return ['wl-copy --type text/plain', 'wl-paste --no-newline']
    elseif executable('xclip') && !empty($DISPLAY)
        return ['xclip -selection clipboard', 'xclip -selection clipboard -o']
    elseif executable('pbcopy') && executable('pbpaste')
        return ['pbcopy', 'pbpaste']
    endif
    return []
endfunction

if has('clipboard')
    " 原生剪贴板：普通 yy 也写入系统剪贴板
    set clipboard=unnamedplus
elseif exists('v:clipproviders') && has('unix')
    " vim 9.1+ provider 机制
    let s:clip_tool = s:DetectClipTool()
    if !empty(s:clip_tool)
        let s:clip_copy_cmd = s:clip_tool[0]
        let s:clip_paste_cmd = s:clip_tool[1]
        function! s:ClipCopy(reg, type, lines) abort
            let l:text = join(a:lines, "\n")
            " 行类型寄存器（V/l）在末尾补换行，与原生 +clipboard / nvim 行为一致；
            " 字符类型（v/c）不加，避免多出换行符。
            if a:type =~# '^[Vl]'
                let l:text .= "\n"
            endif
            call system(s:clip_copy_cmd, l:text)
        endfunction
        function! s:ClipPaste(reg) abort
            return ['', split(system(s:clip_paste_cmd), "\n")]
        endfunction
        " available 回调：运行时重新检查工具+显示环境，SSH/无显示时返回 0，
        " 让 clipmethod 继续尝试下一个方法（如官方 osc52 包）。
        function! s:ClipAvailable() abort
            if s:clip_copy_cmd =~# '^wl-copy'
                return executable('wl-copy') && executable('wl-paste') && !empty($WAYLAND_DISPLAY)
            elseif s:clip_copy_cmd =~# '^xclip'
                return executable('xclip') && !empty($DISPLAY)
            elseif s:clip_copy_cmd =~# '^pbcopy'
                return executable('pbcopy') && executable('pbpaste')
            endif
            return 0
        endfunction
        let v:clipproviders['system'] = {
            \ 'available': function('s:ClipAvailable'),
            \ 'copy': { '+': function('s:ClipCopy'), '*': function('s:ClipCopy') },
            \ 'paste': { '+': function('s:ClipPaste'), '*': function('s:ClipPaste') },
            \ }
        if index(split(&clipmethod, ','), 'system') == -1
            set clipmethod^=system
        endif
        set clipboard=unnamedplus
    endif
    " 官方 osc52 包（vim 9.1 内置）：SSH/远程无显示环境下的兜底，
    " 追加到 clipmethod 末尾，仅在本机工具不可用时才生效。
    silent! packadd osc52
    if index(split(&clipmethod, ','), 'osc52') == -1
        set clipmethod+=osc52
    endif
endif

" =============================================================================
" C 语言语法增强
" =============================================================================

let g:c_space_errors = 1        " 高亮行尾多余空格
let g:c_gnu = 1                 " 识别 GNU C 扩展语法
let g:c_no_cformat = 1          " 不高亮 printf 格式化字符串
let g:c_no_curly_error = 1      " 不将独立的 {} 标记为错误
if exists('g:c_comment_strings')
    unlet g:c_comment_strings   " 不在注释中高亮字符串
endif

" =============================================================================
" 插件管理 (vim-plug)
" =============================================================================
" 安装 vim-plug:
"   curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
"       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
" 使用:
"   :PlugInstall   安装插件
"   :PlugUpdate    更新插件
"   :PlugClean     清理未使用的插件

if exists('*plug#begin') || !empty(globpath(&runtimepath, 'autoload/plug.vim'))
    call plug#begin('~/.vim/plugged')

" ── 文件与导航 ───────────────────────────────────────────────────
Plug 'tpope/vim-vinegar'                                 " 增强内置 netrw 文件浏览
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }     " 模糊搜索引擎
Plug 'junegunn/fzf.vim'                                  " fzf 的 Vim 集成

" ── 编辑增强 ─────────────────────────────────────────────────────
Plug 'tpope/vim-surround'                                " 快速操作括号/引号
Plug 'tpope/vim-repeat'                                  " 让 . 支持插件操作
Plug 'tpope/vim-commentary'                              " gcc 注释当前行
Plug 'tpope/vim-sleuth'                                  " 自动检测缩进风格

" ── Git ──────────────────────────────────────────────────────────
Plug 'tpope/vim-fugitive'                                " Git 命令集成
Plug 'airblade/vim-gitgutter'                            " 左侧栏显示 git diff
Plug 'rbong/vim-flog'                                    " 分支/提交图查看

" ── 语法与格式化 ─────────────────────────────────────────────────
Plug 'dense-analysis/ale'                                " 异步 Lint
Plug 'sbdchd/neoformat'                                  " 一键格式化代码
Plug 'rust-lang/rust.vim'                                " Rust 语法支持

" ── 外观 ─────────────────────────────────────────────────────────
Plug 'itchyny/lightline.vim'                             " 轻量状态栏

    call plug#end()
else
    echohl WarningMsg
    echom 'vim-plug not found: starting Vim without plugins'
    echohl None
endif

" =============================================================================
" 插件配置
" =============================================================================

let mapleader = ","

" ── vim-vinegar ──────────────────────────────────────────────────
" 按 - 打开当前文件所在目录（netrw），再按 - 返回上级
" I 切换隐藏文件显示
let g:netrw_liststyle = 3               " 树形视图

" ── 插件快捷键 ──────────────────────────────────────────────────
" plugin/*.vim 晚于 vimrc 加载，因此等 VimEnter 后再检测插件命令。
function! s:setup_plugin_mappings() abort
    " Ctrl+P 搜索文件（替代已过时的 ctrlp.vim）
    if exists(':Files')
        nnoremap <C-p> :Files<CR>
    endif
    " Ctrl+F 全局搜索文件内容（需要 PATH 中存在 ripgrep）
    if exists(':Rg')
        nnoremap <C-f> :Rg<CR>
    endif
    " 搜索当前打开的 Buffer
    if exists(':Buffers')
        nnoremap <leader>b :Buffers<CR>
    endif
    " vim-flog：查看分支/提交图
    if exists(':Flog')
        nnoremap <leader>gf :Flog<CR>
    endif
    " 手动格式化当前 Buffer
    if exists(':Neoformat')
        nnoremap <silent> <leader>f :Neoformat<CR>
    endif
endfunction

if v:vim_did_enter
    call s:setup_plugin_mappings()
else
    augroup plugin_mappings
        autocmd!
        autocmd VimEnter * ++once call <SID>setup_plugin_mappings()
    augroup END
endif

" ── Git：分支图 + lazygit ────────────────────────────────────────
" lazygit：外部 TUI（需 Vim 支持 :terminal 且已装才启用）
if has('terminal') && executable('lazygit')
  nnoremap <leader>gg :terminal lazygit<CR>
endif

" ── ALE ──────────────────────────────────────────────────────────
let g:ale_sign_error = '✘'
let g:ale_sign_warning = '⚠'
" 仅在保存文件时运行 Lint（避免输入时频繁检查影响性能）
let g:ale_lint_on_text_changed = 'never'
let g:ale_lint_on_insert_leave = 0
let g:ale_lint_on_save = 1

" ── Neoformat ────────────────────────────────────────────────────
" 优先使用项目 node_modules/.bin 中的格式化工具
let g:neoformat_try_node_exe = 1
let g:neoformat_enabled_lua = ['stylua']
let g:neoformat_enabled_python = ['ruff']
let g:neoformat_enabled_javascript = ['biome']
let g:neoformat_enabled_javascriptreact = ['biome']
let g:neoformat_enabled_typescript = ['biome']
let g:neoformat_enabled_typescriptreact = ['biome']
let g:neoformat_enabled_json = ['biome']
let g:neoformat_enabled_jsonc = ['biome']
let g:neoformat_enabled_c = ['clangformat']
let g:neoformat_enabled_cpp = ['clangformat']

" ── Lightline ────────────────────────────────────────────────────
set laststatus=2                        " 始终显示状态栏
set noshowmode                          " lightline 已显示模式，隐藏默认的
let g:lightline = { 'colorscheme': 'wombat' }
