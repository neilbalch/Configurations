set nocompatible              " be iMproved, required
filetype off                  " required

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
set colorcolumn=80

" Set swapfiles store in ~/.cache/vim/swapfiles instead of ./"
set directory=$HOME/.cache/vim/swapfiles

" Set C++ syntax for FRC971 .q Queue definition files
au BufReadPost *.q set syntax=cpp

" Set Python syntax for Bazel .bzl files
augroup filetype
  au! BufRead,BufNewFile *.bzl setfiletype python
augroup end

" Set Python syntax for Bazel BUILD files
augroup filetype
  au! BufRead,BufNewFile BUILD setfiletype python
augroup end

" Map Ctrl+K to clang-format
map <C-k> :pyf /usr/share/vim/addons/syntax/clang-format-3.5.py<CR>
imap <C-k> :pyf /usr/share/vim/addons/syntax/clang-format-3.5.py<CR>i
