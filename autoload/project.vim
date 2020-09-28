"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim-project autoload entry file
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Variables {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:name = 'vim-project'
let s:base = '~'
" Used by statusline
let g:vim_project = {}
" Used by project/main.vim
let g:vim_project_projects = []

"}}}

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Configs {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:GetConfig(name, default)
  let name = 'g:vim_project_'.a:name
  return exists(name) ? eval(name) : a:default
endfunction

function! s:GetConfigPath(prefix)
  let prefix = a:prefix
  if prefix[len(prefix)-1] != '/'
    let prefix = prefix.'/'
  endif
  return expand(prefix.s:name.'/')
endfunction

let s:config_path = s:GetConfigPath(s:GetConfig('config', '~/.vim'))
"}}}

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Functions {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! s:SetBase(base)
  let base = a:base
  if base[len(base)-1] != '/'
    let base = base.'/'
  endif
  let s:base = base
endfunction

function! s:AddProject(path, ...)
  let option = a:0 > 0 ? a:1 : {}
  let fullpath = s:GetFullPath(a:path)
  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  let note = get(option, 'note', '')

  " fullpath includes project name
  " path excludes project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': fullpath,
        \'note': note, 
        \'option': option 
        \}
  call s:InitProjectConfig(project)
  call add(g:vim_project_projects, project)
endfunction

function! s:GetFullPath(path)
  let path = a:path
  if path[0] != '/' && path[0] != '~' && path[1] != ':'
    let path = s:base.path
  endif
  let path = substitute(path, '\/$', '', '')
  return path
endfunction

function! s:InitProjectConfig(project)
  let project = a:project
  let name = project.name
  let config = s:config_path.name

  if !isdirectory(config) && exists('*mkdir')
    " Create config and sessions directory
    call mkdir(config.'/sessions', 'p')

    " Generate init.vim
    let init_file = config.'/init.vim'
    let init_content = [
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'" Initial file after session loaded',
          \'" Project: '.name, 
          \'" Env: $vim_project, $vim_project_config',
          \'" Example: open `src/` on start',
          \'" e $vim_project/src',
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \]
    call writefile(init_content, init_file)

    " Generate quit.vim
    let quit_file = config.'/quit.vim'
    let quit_content = [
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'" Quit file after session saved',
          \'" Project: '.name, 
          \'" Env: $vim_project, $vim_project_config',
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \]
    call writefile(quit_content, quit_file)
  endif
endfunction

function! project#ListProjectNames(A, L, P)
  let projects = deepcopy(g:vim_project_projects)
  let names =  map(projects, {_, project -> "'".project.name."'"})
  return join(names, "\n")
endfunction

function! project#begin()
  command -nargs=1 ProjectBase call s:SetBase(<args>)
  command -nargs=1 Project call s:AddProject(<args>)
endfunction
"}}}

" vim: fdm=marker
