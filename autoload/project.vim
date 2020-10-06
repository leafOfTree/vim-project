"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim-project autoload entry file
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
if exists('g:vim_project_loaded') | finish | endif
let g:vim_project_loaded = 1
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Variables {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:name = 'vim-project'
let s:base = '~'

" Used by statusline
let g:vim_project = {}
let g:vim_project_branch = ''

" Also used by ./project/main.vim
let g:vim_project_projects = []
let g:vim_project_projects_ignore = []

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
let s:auto_indicator = s:GetConfig('auto_indicator', '-')
let s:auto_detect_name = s:GetConfig('auto_detect_name', '.git,.svn,package.json')
let s:auto_detect = s:GetConfig('auto_detect', 'always') " options: 'always', 'ask', 'no'
let s:debug = s:GetConfig('debug', 0)
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
  let index = a:0>1 ? a:2 : len(g:vim_project_projects)
  let fullpath = s:GetFullPath(a:path)
  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  let note = get(option, 'note', '')

  endif

  " fullpath: includes project name
  " path: excludes project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': expand(fullpath),
        \'note': note, 
        \'option': option 
        \}
  if s:IsProjectAutoAdded(project)
    let project.note = empty(project.note) 
          \? s:auto_indicator
          \: project.note.' '.s:auto_indicator
  endif
  call s:InitProjectConfig(project)

  call s:Debug('Add project '.name.', '.path)
  call insert(g:vim_project_projects, project, index)
endfunction

" Ignore path only for auto adding
function! s:IgnoreProject(path)
  let fullpath = s:GetFullPath(a:path)
  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  " fullpath: includes project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': expand(fullpath),
        \}
  call s:Debug('Ignore project '.name.', '.path)
  call add(g:vim_project_projects_ignore, project)
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

function! s:Debug(msg)
  if exists('s:debug') && s:debug
    echom '['.s:name.'] '.a:msg
  endif
endfunction

function! s:Info(msg)
  echom '['.s:name.'] '.a:msg
endfunction

function! project#ListProjectNames(A, L, P)
  let projects = deepcopy(g:vim_project_projects)
  let names =  map(projects, {_, project -> "'".project.name."'"})
  return join(names, "\n")
endfunction

function! project#begin()
  command -nargs=1 ProjectBase call s:SetBase(<args>)
  command -nargs=1 Project call s:AddProject(<args>)
  command -nargs=1 ProjectIgnore call s:IgnoreProject(<args>)

  call s:SourcePluginConfig()
  call s:OnBufEnter()
endfunction

function! s:SourcePluginConfig()
  let add_file = s:config_path.'/add.vim'
  let ignore_file = s:config_path.'/ignore.vim'
  if filereadable(add_file)
    execute 'source '.add_file
  endif
  if filereadable(ignore_file)
    execute 'source '.ignore_file
  endif
endfunction

function! s:SaveToPluginConfigAdd(path)
  let add_file = s:config_path.'/add.vim'
  let cmd = "Project '".a:path."', { 'auto': 1 }"
  call writefile([cmd], add_file, 'a')
endfunction

function! s:SaveToPluginConfigIgnore(path)
  let add_file = s:config_path.'/ignore.vim'
  let cmd = "ProjectIgnore '".a:path."'"
  call writefile([cmd], add_file, 'a')
endfunction

function! s:OnBufEnter()
  augroup vim-project-enter
    autocmd! vim-project-enter
    autocmd BufEnter * call s:AutoloadOnVimEnter()
    if s:auto_detect != 'no'
      autocmd BufEnter * call s:AutoDetectProject()
    endif
  augroup END
endfunction

function! s:AutoloadOnVimEnter()
  if !v:vim_did_enter
    let buf = expand('<amatch>')
    let project = s:GetProjectByFullpath(g:vim_project_projects, buf)
    if !empty(project)
      call s:Debug('Autoload '.project.name)
      ProjectOpen project.name
    endif
  endif
endfunction

function! s:AutoDetectProject()
  if &buftype == ''
    let buf = expand('<amatch>')
    let path = s:GetPathContain(buf, s:auto_detect_name)
    if !empty(path)
      let project = s:GetProjectByFullpath(g:vim_project_projects, path)
      let ignore = s:GetProjectByFullpath(
            \g:vim_project_projects_ignore, path)

      if empty(project) && empty(ignore)
        let path = substitute(path, expand('~'), '~', '')
        if s:auto_detect == 'always'
          call s:AutoAddProject(path)
        else
          call s:Info('New repo found at "'.path
                \.'". Do you want to add it? (Press y to confirm)')
          let c = getchar()
          let char = type(c) == v:t_string ? c : nr2char(c)
          if char ==? 'y'
            call s:AutoAddProject(path)
          else
            call s:AutoIgnoreProject(path)
          endif
        endif
      endif
    endif
  endif
endfunction

function! s:AutoAddProject(path)
  let index = s:FindLastAutoAddProjectIndex()
  call s:AddProject(a:path, { 'auto': 1 }, index)
  call s:SaveToPluginConfigAdd(a:path)
  redraw
  call s:Info('Project added')
endfunction

function! s:AutoIgnoreProject(path)
  call s:IgnoreProject(a:path)
  call s:SaveToPluginConfigIgnore(a:path)
  redraw
  call s:Info('Project ignored')
endfunction

function! s:FindLastAutoAddProjectIndex()
  let projects = g:vim_project_projects
  let i = 0
  let index = i
  for project in projects
    let i = i + 1
    if s:IsProjectAutoAdded(project)
      let index = i
    endif
  endfor
  return index
endfunction

function! s:IsProjectAutoAdded(project)
  return has_key(a:project.option, 'auto') && a:project.option.auto
endfunction

function! s:GetPathContain(buf, pat)
  let segments = split(a:buf, '/\|\\', 1)
  let depth = len(segments)
  let pats = split(a:pat, ',')

  for i in range(0, depth-1)
    let path = join(segments[0:depth-1-i], '/')
    for p in pats
      let matches = globpath(path, p, 1, 1)
      if len(matches) > 0
        return path
      endif
    endfor
  endfor
endfunction

function! s:GetProjectByFullpath(projects, fullpath)
  for project in a:projects
    if project.fullpath == a:fullpath
      return project
    endif
  endfor

  return {}
endfunction
"}}}

" vim: fdm=marker
