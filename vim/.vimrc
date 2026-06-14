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

" 持久化 undo：关闭文件后重新打开仍可撤销之前的操作
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
syntax on
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
" Vim 8.0.210+ 已内置 bracketed paste 支持，以下仅为旧版本兜底
" =============================================================================

if !has('patch-8.0.210')
    " 进入插入模式时，通知终端开启 bracketed paste 协议
    let &t_SI .= "\<Esc>[?2004h"
    " 退出插入模式时，关闭该协议
    let &t_EI .= "\<Esc>[?2004l"
    " 收到终端的"粘贴开始"信号 ESC[200~ 时，自动进入 paste 模式
    inoremap <special> <expr> <Esc>[200~ XTermPasteBegin()

    function! XTermPasteBegin()
        " 收到终端的"粘贴结束"信号 ESC[201~ 时，自动退出 paste 模式
        set pastetoggle=<Esc>[201~
        set paste
        return ""
    endfunction
endif

if v:version >= 800
    " 防止同一文件被多个 Vim 实例同时编辑（尝试跳转到已打开的实例）
    packadd! editexisting
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

" ── 语法与格式化 ─────────────────────────────────────────────────
Plug 'dense-analysis/ale'                                " 异步 Lint
Plug 'sbdchd/neoformat'                                  " 一键格式化代码
Plug 'rust-lang/rust.vim'                                " Rust 语法支持

" ── 外观 ─────────────────────────────────────────────────────────
Plug 'itchyny/lightline.vim'                             " 轻量状态栏

call plug#end()

" =============================================================================
" 插件配置
" =============================================================================

let mapleader = ","

" ── vim-vinegar ──────────────────────────────────────────────────
" 按 - 打开当前文件所在目录（netrw），再按 - 返回上级
" I 切换隐藏文件显示
let g:netrw_liststyle = 3               " 树形视图

" ── fzf.vim 快捷键 ──────────────────────────────────────────────
" Ctrl+P 搜索文件（替代已过时的 ctrlp.vim）
nnoremap <C-p> :Files<CR>
" Ctrl+F 全局搜索文件内容（需要系统安装 ripgrep: brew install ripgrep）
nnoremap <C-f> :Rg<CR>
" 搜索当前打开的 Buffer
nnoremap <leader>b :Buffers<CR>

" ── ALE ──────────────────────────────────────────────────────────
let g:ale_sign_error = '✘'
let g:ale_sign_warning = '⚠'
" 仅在保存文件时运行 Lint（避免输入时频繁检查影响性能）
let g:ale_lint_on_text_changed = 'never'
let g:ale_lint_on_insert_leave = 0
let g:ale_lint_on_save = 1

" ── Neoformat ────────────────────────────────────────────────────
" 保存时自动格式化
augroup fmt
    autocmd!
    autocmd BufWritePre * undojoin | Neoformat
augroup END
" 优先使用项目本地的 formatter 配置
let g:neoformat_try_node_exe = 1

" ── Lightline ────────────────────────────────────────────────────
set laststatus=2                        " 始终显示状态栏
set noshowmode                          " lightline 已显示模式，隐藏默认的
let g:lightline = { 'colorscheme': 'wombat' }
