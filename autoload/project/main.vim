"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim-project autoload main file
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Variables {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:name = 'vim-project'
let s:prompt_prefix = 'Open a project:'
let s:prompt_suffix = ''
let s:laststatus_save = &laststatus
let s:origin_height = 0
let s:head_file_job = 0
let s:project = {}
let s:branch = ''
let s:branch_default = '__default__'
let s:list_buffer = '__projects__'
let s:nerdtree_tmp = '__nerdtree_tmp__'
let s:vim_project_prompt_mapping_default = {
      \'closeList': "\<Esc>",
      \'clearChar': ["\<bs>", "\<c-a>"],
      \'clearWord': "\<c-w>",
      \'clearAllInput': "\<c-u>",
      \'prevItem': "\<c-k>",
      \'nextItem': "\<c-j>",
      \'firstItem': "\<c-h>",
      \'lastItem': "\<c-l>",
      \'openProject': "\<cr>",
      \}

" For statusline
let g:vim_project = {}
let g:vim_project_branch = ''
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
let s:start_from_home = s:GetConfig('start_from_home', 0)
let s:ignore_branch = s:GetConfig('ignore_branch', 0)
let s:ignore_session = s:GetConfig('ignore_session', 0)
let s:prompt_mapping = s:GetConfig('prompt_mapping', 
      \s:vim_project_prompt_mapping_default)
let s:debug = s:GetConfig('debug', 0)
"}}}

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Functions {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! project#main#ListProjects()
  call s:OpenListBuffer()
  call s:SetupListBuffer()
  call s:HandleInput()
endfunction

function! s:OpenListBuffer()
  let output_win = s:list_buffer
  let output_num = bufwinnr(output_win)
  if output_num == -1
    execute 'botright split '.output_win
  else
    execute output_num.'wincmd w'
  endif
endfunction

function! s:CloseListBuffer()
  let &g:laststatus = s:laststatus_save
  quit
  redraw!
endfunction

function! s:SetupListBuffer()
  setlocal buftype=nofile bufhidden=delete filetype=projectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set laststatus=0
  nnoremap<buffer> <esc> :quit<cr>
  highlight! link SignColumn Noise
  highlight SelectedRow gui=reverse term=reverse cterm=reverse
  sign define selected text=> texthl=SelectedRow linehl=SelectedRow 
endfunction

function! s:ShowProjects(...)
  let bufname = expand('%')
  " Avoid clearing some other files by mistake
  if bufname != s:list_buffer
    return
  endif
  let input = a:0>0 ? a:1 : ''
  let offset = a:0>1 ? a:2 : { 'value': 0 }

  normal! ggdG

  let projects = s:SortAndFilterList(input, 
        \copy(g:vim_project_projects))
  let result = s:GetDisplayList(projects)

  let result_len = len(result)
  execute 'resize'.' '.result_len
  sign unplace 9
  if result_len > 0
    call append(0, result)

    let lastline = result_len
    if offset.value > 0
      let offset.value = 0
    elseif lastline + offset.value < 1
      let offset.value = 1 - lastline
    endif
    let lastline += offset.value
    execute 'sign place 9 line='.lastline.' name=selected'
  endif
  call s:KeepOriginHeight(result_len)

  " Remove extra blank lines
  normal! Gdd
  normal! gg 
  normal! G 

  return projects
endfunction

function! s:KeepOriginHeight(height)
  if a:height < s:origin_height
    let counts = s:origin_height - a:height
    call append(0, repeat([''], counts))
    execute 'resize '.s:origin_height
  endif
endfunction

function! s:FilterList(filter, list)
  let filter = a:filter
  let list = a:list

  for item in list
    let item._sort_type = ''
    let item._sort_index = -1

    let match_index = match(item.name, filter)
    if match_index != -1
      let item._sort_type = 'name'
      let item._sort_index = match_index
    endif

    if item._sort_type != 'name'
      if has_key(item.option, 'note')
        let match_index = match(item.option.note, filter)
        if match_index != -1
          let item._sort_type = 'note'
          let item._sort_index = match_index
        endif
      endif
    endif

    if item._sort_type == ''
      let match_index = match(item.path, filter)
      if match_index != -1
        let item._sort_type = 'path'
        let item._sort_index = match_index
      endif
    endif
  endfor
  let result = filter(list, { _, value -> value._sort_type != '' })
  return result
endfunction

function! s:SortAndFilterList(filter, list)
  let list = a:list
  if a:filter == ''
    return list
  endif
  let filters = split(a:filter, ' ')

  let result = []
  for filter in filters
    let result = s:FilterList(filter, list)
  endfor
  return result
endfunction

function! s:AddRightPadding(string, length)
  let padding = repeat(' ', a:length - len(a:string))
  return a:string.padding
endfunction

function! s:FormatProjects()
  let list = g:vim_project_projects
  let max = {}
  for item in list
    for key in keys(item)
      if !has_key(max, key) 
            \|| (type(item[key]) == v:t_string && len(item[key]) > max[key])
        let max[key] = len(item[key])
      endif
    endfor
  endfor

  for item in list
    for key in keys(item)
      if type(item[key]) == v:t_string
        let item['__'.key] = s:AddRightPadding(item[key], max[key])
      endif
    endfor
  endfor
  return list
endfunction

function! s:GetPromptCommand(char)
  let command = ''
  for [key, value] in items(s:prompt_mapping)
    if type(value) == v:t_string
      let match = value == a:char
    else
      let match = count(value, a:char) > 0
    endif
    if match
      let command = key
      break
    endif
  endfor
  return command
endfunction

function! s:HandleInput()
  " Init
  call s:FormatProjects()
  let projects = s:ShowProjects()
  let s:origin_height = len(projects)
  redraw
  echo s:prompt_prefix.' '.s:prompt_suffix

  " Read input
  let input = ''
  let offset = { 'value': 0 }
  try
    while 1
      let c = getchar()
      let char = type(c) == v:t_string ? c : nr2char(c)
      let cmd = s:GetPromptCommand(char)
      if cmd == 'closeList'
        call s:CloseListBuffer()
        break
      elseif cmd == 'clearChar'
        let input = len(input) == 1 ? '' : input[0:len(input)-2]
      elseif cmd == 'clearWord'
        let input = substitute(input, '\S*\s*$', '', '')
      elseif cmd == 'clearAllInput'
        let input = ''
      elseif cmd == 'prevItem'
        let offset.value -= 1
      elseif cmd == 'nextItem'
        let offset.value += 1
      elseif cmd == 'firstItem'
        let offset.value = 1 - len(projects) 
      elseif cmd == 'lastItem'
        let offset.value = 0
      elseif cmd == 'openProject'
        call s:CloseListBuffer()
        let index = len(projects) - 1 + offset.value
        let project = projects[index]
        call s:OpenProject(project)
        break
      else
        let input = input.char
      endif

      let projects = s:ShowProjects(input, offset)

      redraw
      echo s:prompt_prefix.' '.input.s:prompt_suffix
    endwhile
  catch /^Vim:Interrupt$/
    call s:Debug('interrupt')
  endtry
endfunction

function! s:GetProjectByName(name)
  let projects = g:vim_project_projects
  for project in projects
    if project.name == a:name
      return project
    endif
  endfor

  return {}
endfunction

function! project#main#OpenProjectByName(name)
  let project = s:GetProjectByName(a:name)
  if !empty(project)
    call s:OpenProject(project)
  else
    call s:Log('Project not found: '.name)
  endif
endfunction

function! s:OpenProject(project)
  let current = a:project
  let prev = s:project

  if prev != current
    if !empty(prev)
      call s:Debug('Save previous project: '.prev.name)
      call s:SaveSession()
    endif
    let s:project = current

    call s:Info('Open project: '.s:project.name)
    call s:LoadProject()
    call s:SetEnvVariables()
    call s:SyncGlobalVariables()
  else
    call s:Info('Project already opened')
  endif
endfunction

function! s:SetEnvVariables()
    let $vim_project = s:project.fullpath
    let $vim_project_config = s:config_path.s:project.name
endfunction

function! s:UnsetEnvVariables()
    unlet $vim_project
    unlet $vim_project_config
endfunction

function! s:IsProjectExist()
  if empty(s:project)
    call s:Debug('No project opened')
    return 0
  else
    return 1
  endif
endfunction

function! project#main#OpenProjectHome()
  if s:IsProjectExist()
    edit $vim_project
  endif
endfunction

function! project#main#OpenProjectConfig()
  if s:IsProjectExist()
    execute 'edit '.s:config_path.s:project.name
  endif
endfunction

function! project#main#ExitProject()
  if s:IsProjectExist()
    call s:Info('Exit project: '.s:project.name)
    call s:SaveSession()
    call s:SourceExitFile()

    let s:project = {}
    call s:UnsetEnvVariables()
    call s:SyncGlobalVariables()
  endif
endfunction

function! s:SyncGlobalVariables()
  if !empty(s:project)
    let g:vim_project = { 
          \'name': s:project.name, 
          \'path': s:project.path,
          \'fullpath': s:project.fullpath,
          \'option': s:project.option
          \}
  else
    let g:vim_project = {}
  endif
  let g:vim_project_branch = s:branch
endfunction

function! project#main#ShowProjectInfo()
  if !empty(s:project)
    call s:Info('Name: '.s:project.name.', path: '.s:project.path)
  else
    call s:Info('No project opened')
  endif
endfunction

function! s:LoadProject()
  enew
  call s:FindBranch()
  call s:LoadSession()
  call s:SetStartBuffer()

  call s:SourceInitFile()
  call s:SaveOnVimLeave()
endfunction

function! s:SetStartBuffer()
  let buftype = &buftype
  let bufname = expand('%')

  let fromHome = s:start_from_home
        \ || &buftype == 'nofile' 
        \ || bufname == '' 
        \ || bufname == s:nerdtree_tmp
  if fromHome
    if bufname == s:nerdtree_tmp
      setlocal bufhidden=delete
      setlocal filetype=
    endif
    call s:Debug('Start from home')
    execute 'silent only | edit '.s:project.fullpath
  endif
endfunction

function! s:SaveOnVimLeave()
  augroup vim-project
    autocmd! vim-project
    autocmd VimLeavePre * call project#main#ExitProject()
  augroup END
endfunction

function! s:SourceInitFile()
  call s:SourceFile('init.vim')
endfunction

function! s:SourceExitFile()
  call s:SourceFile('quit.vim')
endfunction

function! s:SourceFile(file)
  let config_path = s:config_path.s:project.name
  let file = config_path.'/'.a:file
  if filereadable(file)
    call s:Debug('Source file: '.file)
    execute 'source '.file
  else
    call s:Debug('Not found file: '.file)
  endif
endfunction

function! s:FindBranch(...)
  if s:ignore_branch
    let s:branch = s:branch_default
    return
  endif

  let project = a:0>0 ? a:1 : s:project
  let head_file = expand(project.fullpath.'/.git/HEAD')

  if filereadable(head_file)
    let head = join(readfile(head_file), "\n")

    if !v:shell_error
      let s:branch = matchstr(head, 'refs\/heads\/\zs\w*')
    else
      call s:Error('Error on find branch: '.v:shell_error)
      let s:branch = s:branch_default
    endif
    call s:Debug('Find branch: '.s:branch)
  else
    call s:Info('Not a git repository')
    let s:branch = s:branch_default
  endif
endfunction

function! s:GetSessionFile()
  if s:IsProjectExist()
    let config_path = s:config_path.s:project.name
    return config_path.'/sessions/'.s:branch.'.vim'
  else
    return ''
  endif
endfunction

function! s:LoadSession(...)
  if s:ignore_session
    return
  endif

  let file = s:GetSessionFile()
  if filereadable(file)
    call s:Debug('Load session file: '.file)
    execute 'source '.file
  else
    call s:Debug('Not found session file: '.file)
  endif

  let reload = a:0>0 ? a:1 : 0
  if !reload && !s:ignore_branch && executable('tail') == 1
    if exists('*job_start')
      call s:WatchHeadFileVim()
    elseif exists('*jobstart')
      call s:WatchHeadFileNeoVim()
    endif
  endif
endfunction

function! s:GetWatchCmd()
  let head_file = expand(s:project.fullpath.'/.git/HEAD')
  call s:Debug('Watching .git head file: '.head_file)
  let cmd = 'tail -n0 -F '.head_file
  return cmd
endfunction

function! s:WatchHeadFileVim()
  let cmd = s:GetWatchCmd()
  if type(s:head_file_job) == v:t_job
    call job_stop(s:head_file_job)
  endif
  let s:head_file_job = job_start(cmd, 
        \ { 'callback': 'ReloadSession' })
endfunction

function! s:WatchHeadFileNeoVim()
  let cmd = s:GetWatchCmd()
  if s:head_file_job 
    call jobstop(s:head_file_job)
  endif
  let s:head_file_job = jobstart(cmd, 
        \ { 'on_stdout': 'ReloadSession' })
endfunction

function! s:SaveSession()
  if s:ignore_session
    return
  endif

  if s:IsProjectExist()
    call s:BeforeSaveSession()

    let file = s:GetSessionFile()
    call s:Debug('Save session to: '.file)
    execute 'mksession! '.file

    call s:AfterSaveSession()
  endif
endfunction

let s:nerdtree_out = 0
let s:nerdtree_in = 0
function! s:BeforeSaveSession()
  let has_nerdtree = exists('g:loaded_nerd_tree') 
        \&& g:NERDTree.IsOpen()
  if has_nerdtree
    if &filetype != 'nerdtree'
      call s:Debug('Close other nerdtree first')
      let s:nerdtree_out = 1
      NERDTreeClose
    else
      call s:Debug('Clear nerdtree setting')
      let s:nerdtree_in = 1
      let s:nerdtree_in_file = expand('%')
      setlocal filetype=
      setlocal syntax=
      execute 'file '.s:nerdtree_tmp 
    endif
  endif
endfunction

function! s:AfterSaveSession()
  if s:nerdtree_out
    let s:nerdtree_out = 0
    call s:Debug('Recover nerdtree')
    NERDTreeToggle
    wincmd p
  endif
  if s:nerdtree_in
    call s:Debug('Recover nerdtree setting')
    let s:nerdtree_in = 0
    silent! setlocal filetype=nerdtree
    setlocal syntax=nerdtree
    execute 'file '.s:nerdtree_in_file
  endif
endfunction

function! ReloadSession(channel, msg, ...)
  if type(a:msg) == v:t_list
    let msg = join(a:msg)
  else
    let msg = a:msg
  endif

  call s:Debug('Trigger reload, msg: '.msg)

  if empty(msg)
    return
  endif

  let new_branch = matchstr(msg, 'refs\/heads\/\zs\w*')
  if !empty(new_branch) && new_branch != s:branch
    call s:Info('Change branch and reload: '.new_branch)
    call s:SaveSession()

    let s:branch = new_branch
    let g:vim_project_branch = s:branch

    call s:LoadSession(1)
    call s:SetStartBuffer()
  endif
endfunction

function! s:GetDisplayList(list)
  let list = copy(a:list)
  return map(list, function('s:GetDisplayRow'))
endfunction

function! s:GetDisplayRow(key, value)
  let value = a:value
  return value.__name."  ".value.__note."   ".value.__path
endfunction

function! s:Debug(msg)
  if exists('s:debug') && s:debug
    echom '['.s:name.'] '.a:msg
  endif
endfunction

function! s:Error(msg)
  echoerr '['.s:name.']'.a:msg
endfunction

function! s:Info(msg)
  echom '['.s:name.'] '.a:msg
endfunction
"}}}

" vim: fdm=marker
