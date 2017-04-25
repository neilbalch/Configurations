set nocompatible              " be iMproved, required
filetype off                  " required

" set the runtime path to include Vundle and initialize
set rtp+=~/.vim/bundle/Vundle.vim
call vundle#begin()
" alternatively, pass a path where Vundle should install plugins
"call vundle#begin('~/some/path/here')

" let Vundle manage Vundle, required
Plugin 'VundleVim/Vundle.vim'

" Auto completion
Plugin 'Valloric/YouCompleteMe'

" Alternate
Plugin 'vim-scripts/a.vim'

" All of your Plugins must be added before the following line
call vundle#end()            " required
filetype plugin indent on    " required
" To ignore plugin indent changes, instead use:
"filetype plugin on
"
" Brief help
" :PluginList       - lists configured plugins
" :PluginInstall    - installs plugins; append `!` to update or just :PluginUpdate
" :PluginSearch foo - searches for foo; append `!` to refresh local cache
" :PluginClean      - confirms removal of unused plugins; append `!` to auto-approve removal
"
" see :h vundle for more details or wiki for FAQ
" Put your non-Plugin stuff after this line

highligh ExtraWhitespace ctermbg=red guibg=red
match ExtraWhitespace /\s\+$/

syntax on
set clipboard=unnamed
set nu
set background=dark
set ts=2
set hlsearch
set mouse=ar
set selectmode+=mouse
set expandtab
set tabstop=2
set shiftwidth=2
set autoindent
set clipboard=unnamed

" Set swapfiles store in ~/.vim_runtime instead of ./"
set directory=$HOME/.vim_runtime/swapfiles//

map <C-k> :pyf /usr/share/vim/addons/syntax/clang-format-3.5.py<CR>
imap <C-k> :pyf /usr/share/vim/addons/syntax/clang-format-3.5.py<CR>i
