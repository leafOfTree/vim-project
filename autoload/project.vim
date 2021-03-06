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
let s:base = '~/'
let s:add_file = '_add.vim'
let s:ignore_file = '_ignore.vim'
let s:from_auto = 0

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
  return expand(prefix.s:name.'-config/')
endfunction

let s:config_path = s:GetConfigPath(s:GetConfig('config', '~/.vim'))
let s:auto_indicator = s:GetConfig('auto_indicator', '')
let s:auto_detect_sign = s:GetConfig(
      \'auto_detect_sign',
      \'.git,.svn,package.json',
      \)

" options: 'always', 'ask', 'no'
let s:auto_detect = s:GetConfig('auto_detect', 'ask') 
let s:autoload_on_start = s:GetConfig('autoload_on_start', 0) 
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
  let fullpath = s:GetFullPath(a:path)
  if !isdirectory(fullpath)
    call s:Info('No directory: '.fullpath)
    return
  endif
  let hasProject = s:HasProjectWithSameFullPath(
        \fullpath,
        \g:vim_project_projects
        \)
  if hasProject
    call s:Debug('Project has already been added at '.fullpath)
    return
  endif

  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  let option = a:0 > 0 ? a:1 : {}
  let note = get(option, 'note', '')
  if s:from_auto
    let note = empty(note) ? s:auto_indicator : note.' '.s:auto_indicator
  endif

  " fullpath: with project name
  " path: without project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': fullpath,
        \'note': note, 
        \'auto': s:from_auto,
        \'option': option,
        \}
  call s:InitProjectConfig(project)
  call s:Debug('Added project '.name.', '.path)
  let index = a:0>1 ? a:2 : len(g:vim_project_projects)
  call insert(g:vim_project_projects, project, index)
endfunction

function! s:HasProjectWithSameFullPath(fullpath, projects)
  let result = 0
  for project in a:projects
    if project.fullpath == a:fullpath
      let result = 1
    endif
  endfor
  return result
endfunction

" Ignore path only for auto adding
function! s:IgnoreProject(path)
  let fullpath = s:GetFullPath(a:path)
  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  " path: excludes project name
  " fullpath: includes project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': fullpath,
        \}
  call s:Debug('Ignore project '.name.', '.path)
  call add(g:vim_project_projects_ignore, project)
endfunction

function! s:GetFullPath(path)
  let path = a:path
  if path[0] != '/' && path[0] != '~' && path[1] != ':'
    let path = s:base.path
  endif
  let path = substitute(expand(path), '\', '\/', 'g')
  let path = substitute(path, '\/$', '', '')
  return path
endfunction

function! s:InitProjectConfig(project)
  let name = a:project.name
  let config_path = s:GetProjectConfigPath(s:config_path, a:project)

  if !isdirectory(config_path) && exists('*mkdir')
    " Create config and sessions directory
    call mkdir(config_path.'/sessions', 'p')

    " Generate init.vim
    let init_file = config_path.'/init.vim'
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
    let quit_file = config_path.'/quit.vim'
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
  if s:debug
    echom '['.s:name.'] '.a:msg
  endif
endfunction

function! s:Info(msg)
  echom '['.s:name.'] '.a:msg
endfunction

function! s:InfoHl(msg)
  echohl Statement | echon '['.s:name.'] ' | echohl None |
        \echon a:msg
endfunction

function! s:GetProjectConfigPath(config_path, project)
  let id = substitute(a:project.path, '/', '_', 'g')
  let folder = a:project.name.'__'.id
  return a:config_path.folder
endfunction

function! project#GetProjectConfigPath(config_path, project)
  return s:GetProjectConfigPath(a:config_path, a:project)
endfunction

function! project#ListProjectNames(A, L, P)
  let projects = deepcopy(g:vim_project_projects)
  let names =  map(projects, {_, project -> "'".project.name."'"})
  return join(names, "\n")
endfunction

" Call this entry function first
function! project#begin()
  command -nargs=1 ProjectBase call s:SetBase(<args>)
  command -nargs=1 Project call s:AddProject(<args>)
  command -nargs=1 ProjectIgnore call s:IgnoreProject(<args>)

  call s:SourcePluginConfigFiles()
  call s:WatchOnBufEnter()
endfunction

function! s:SourcePluginConfigFiles()
  let add_file = s:config_path.'/'.s:add_file
  let ignore_file = s:config_path.'/'.s:ignore_file
  if filereadable(add_file)
    let s:from_auto = 1
    execute 'source '.add_file
    let s:from_auto = 0
  endif
  if filereadable(ignore_file)
    execute 'source '.ignore_file
  endif
endfunction

function! s:SaveToPluginConfigAdd(path)
  let file = s:config_path.'/'.s:add_file
  let cmd = "Project '".a:path."'"
  call writefile([cmd], file, 'a')
endfunction

function! s:SaveToPluginConfigIgnore(path)
  let file = s:config_path.'/'.s:ignore_file
  let cmd = "ProjectIgnore '".a:path."'"
  call writefile([cmd], file, 'a')
endfunction

function! s:WatchOnBufEnter()
  augroup vim-project-enter
    autocmd! vim-project-enter
    if s:autoload_on_start
      " The event order is BufEnter then VimEnter
      autocmd BufEnter * ++once call s:PreCheckOnBufEnter()
      autocmd VimEnter * ++once call s:AutoloadOnVimEnter()
    endif
    if s:auto_detect != 'no'
      autocmd BufEnter * call s:AutoDetectProject()
    endif
  augroup END
endfunction

let s:startup_project = {}
let s:startup_buf = ''
function! s:PreCheckOnBufEnter()
  if !v:vim_did_enter
    let buf = expand('<amatch>')
    let s:startup_buf = buf
    let project = s:GetProjectByFullpath(g:vim_project_projects, buf)
    if empty(project)
      let path = s:GetPathContain(buf, s:auto_detect_sign)
      if !empty(path)
        let project = s:GetProjectByFullpath(g:vim_project_projects, path)
      endif
    endif

    if !empty(project)
      let s:startup_project = project
    endif
  endif
endfunction

function! VimProject_HandleFileManagerPlugin(timer)
  if expand('%:p') =~ 'NetrwTreeListing'
    " For Netrw
    Explore
  else
    " For Nerdtree, Fern, ...
    silent! edit
  endif
endfunction

function! VimProject_DoBufRead(timer)
  doautoall BufRead
endfunction

function! s:AutoloadOnVimEnter()
  let project = s:startup_project
  if !empty(project)
    let buf = expand('<amatch>')
    " Avoid conflict with opened buffer like nerdtree
    enew
    ProjectOpen project.name

    if project.fullpath is s:startup_buf
      " Follow session files if open the root path
      " Use timer to avoid conflict with Fern.vim
      call timer_start(1, 'VimProject_HandleFileManagerPlugin')
    else
      " Otherwise edit the current file
      execute 'edit '.s:startup_buf
    endif
    call timer_start(1, 'VimProject_DoBufRead')
  endif
endfunction

function! s:AutoDetectProject()
  if &buftype == ''
    let buf = expand('<amatch>')
    let path = s:GetPathContain(buf, s:auto_detect_sign)
    if !empty(path)
      let project = s:GetProjectByFullpath(g:vim_project_projects, path)
      let ignore = s:GetProjectByFullpath(
            \g:vim_project_projects_ignore, path)

      if empty(project) && empty(ignore)
        let path = substitute(path, expand('~'), '~', '')
        if s:auto_detect == 'always'
          call s:AutoAddProject(path)
        else
          redraw
          echohl Statement | echon '[vim-project] ' | echohl None
          echon 'Would you like to add "'
          echohl String | echon path | echohl None
          echon '"? ['
          echohl Statement | echon "Y" | echohl None
          echon '/'
          echohl Statement | echon "n" | echohl None
          echon ']'

          while 1
            let c = getchar()
            let char = type(c) == v:t_string ? c : nr2char(c)
            if char ==? 'y'
              call s:AutoAddProject(path)
              break
            endif
            if char ==? 'n'
              call s:AutoIgnoreProject(path)
              break
            endif
            if char == "\<esc>"
              redraw
              call s:InfoHl('Project skipped at this time')
              break
            endif
          endwhile
        endif
      endif
    endif
  endif
endfunction

function! s:AutoAddProject(path)
  let index = s:FindLastAutoAddProjectIndex()
  let s:from_auto = 1
  call s:AddProject(a:path, {}, index)
  let s:from_auto = 0
  call s:SaveToPluginConfigAdd(a:path)
  call s:SaveToPluginConfigIgnore(a:path)
  redraw
  call s:InfoHl('Added '.a:path)
endfunction

function! s:AutoIgnoreProject(path)
  call s:IgnoreProject(a:path)
  call s:SaveToPluginConfigIgnore(a:path)
  redraw
  call s:InfoHl('Ignored '.a:path)
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
  return a:project.auto
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
    if project.fullpath is a:fullpath
      return project
    endif
  endfor

  return {}
endfunction
"}}}

" vim: fdm=marker
