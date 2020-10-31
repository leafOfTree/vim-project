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
let s:nerdtree_tmp = '__vim_project_nerdtree_tmp__'
let s:format_cache = 0
let s:vim_project_prompt_mapping_default = {
      \'open_project': "\<cr>",
      \'close_list': "\<esc>",
      \'clear_char': ["\<bs>", "\<c-a>"],
      \'clear_word': "\<c-w>",
      \'clear_all': "\<c-u>",
      \'prev_item': ["\<c-k>", "\<up>"],
      \'next_item': ["\<c-j>", "\<down>"],
      \'first_item': ["\<c-h>", "\<left>"],
      \'last_item': ["\<c-l>", "\<right>"],
      \'next_view': "\<tab>",
      \'prev_view': "\<s-tab>",
      \}

" For statusline and autoload/project.vim
let g:vim_project = {}
let g:vim_project_branch = ''
"}}}


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Config helpers {{{
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

function! s:MergePromptMapping()
  if s:prompt_mapping != s:vim_project_prompt_mapping_default
    for [key, value] in items(s:vim_project_prompt_mapping_default)
      if !has_key(s:prompt_mapping, key)
        let s:prompt_mapping[key] = s:vim_project_prompt_mapping_default[key]
      endif
    endfor
  endif
endfunction
"}}}

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Configs {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:config_path = s:GetConfigPath(s:GetConfig('config', '~/.vim'))
let s:open_root = s:GetConfig('open_root', 0)
let s:ignore_branch = s:GetConfig('ignore_branch', 0)
let s:ignore_session = s:GetConfig('ignore_session', 0)
let s:prompt_mapping = s:GetConfig('prompt_mapping', 
      \s:vim_project_prompt_mapping_default)
call s:MergePromptMapping()

let s:views = s:GetConfig('views', [])
let s:view_index = -1
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
    execute 'noautocmd botright split '.output_win
  else
    execute output_num.'wincmd w'
  endif
endfunction

function! s:CloseListBuffer()
  let &g:laststatus = s:laststatus_save
  quit
  redraw!
  wincmd p
endfunction

function! s:SetupListBuffer()
  setlocal buftype=nofile bufhidden=delete filetype=projectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set laststatus=0
  nnoremap<buffer> <esc> :quit<cr>
  highlight! link SignColumn Noise
  highlight ProjectSelected gui=reverse term=reverse cterm=reverse
  sign define selected text=> texthl=ProjectSelected linehl=ProjectSelected 
endfunction

function! s:ShowProjects(...)
  let bufname = expand('%')
  " Avoid clearing other files by mistake
  if bufname != s:list_buffer
    return
  endif
  let input = a:0>0 ? a:1 : ''
  let offset = a:0>1 ? a:2 : { 'value': 0 }

  normal! ggdG

  let projects = s:FilterProjects(
        \copy(g:vim_project_projects),
        \input, 
        \)
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
  if input == ''
    let s:origin_height = len(projects)
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

function! s:FilterList(list, filter)
  let list = a:list
  let filter = a:filter

  for item in list
    let item._match_type = ''
    let item._match_index = -1

    let match_index = match(item.name, filter)
    if match_index != -1
      let item._match_type = 'name'
      let item._match_index = match_index
    endif

    if item._match_type != 'name'
      if has_key(item.option, 'note')
        let match_index = match(item.option.note, filter)
        if match_index != -1
          let item._match_type = 'note'
          let item._match_index = match_index
        endif
      endif
    endif

    if item._match_type == ''
      let match_index = match(item.path, filter)
      if match_index != -1
        let item._match_type = 'path'
        let item._match_index = match_index
      endif
    endif
  endfor
  call filter(list, { _, value -> value._match_type != '' })
  call sort(list, 's:SortList')
  return list
endfunction

function! s:SortList(a1, a2)
  let type1 = a:a1._match_type
  let type2 = a:a2._match_type
  let index1 = a:a1._match_index
  let index2 = a:a2._match_index
  if type1 == 'name' && type2 != 'name'
    return 1
  endif
  if type1 == 'note' && type2 == 'path'
    return 1
  endif
  if type1 == type2
    return index2 - index1
  endif
  return -1
endfunction

function! s:FilterListName(list, filter, reverse)
  let list = a:list
  let filter = a:filter
  call filter(list, { _, value -> empty(filter) || 
        \(!a:reverse  ? value.name =~ filter : value.name !~ filter)
        \})
  return list
endfunction

function! s:NextView()
  let max = len(s:views)
  let s:view_index = s:view_index < max ? s:view_index + 1 : 0
endfunction

function! s:PreviousView()
  let max = len(s:views)
  let s:view_index = s:view_index > 0 ? s:view_index - 1 : max 
endfunction

function! s:FilterProjectsByView(projects)
  let max = len(s:views)
  if s:view_index >= 0 && s:view_index < max
    let view = s:views[s:view_index]
    if len(view) == 2
      let [show, hide] = view
    elseif len(view) == 1
      let show = view[0]
      let hide = ''
    else
      let show = ''
      let hide = ''
    endif
    call s:FilterListName(a:projects, show, 0)
    call s:FilterListName(a:projects, hide, 1)
  endif
endfunction

function! s:FilterProjects(projects, filter)
  let projects = a:projects
  call s:FilterProjectsByView(projects)

  if a:filter != ''
    for filter in split(a:filter, ' ')
      call s:FilterList(projects, filter)
    endfor
  endif

  return projects
endfunction

function! s:AddRightPadding(string, length)
  let padding = repeat(' ', a:length - len(a:string))
  return a:string.padding
endfunction

function! s:FormatProjects()
  let list = g:vim_project_projects
  if s:format_cache == len(list)
    return
  else
    let s:format_cache = len(list)
  endif

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
      if type(item[key]) == v:t_string && key[0:1] != '__'
        let item['__'.key] = s:AddRightPadding(item[key], max[key])
      endif
    endfor
  endfor
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
      if cmd == 'close_list'
        call s:CloseListBuffer()
        break
      elseif cmd == 'clear_char'
        let input = len(input) == 1 ? '' : input[0:len(input)-2]
      elseif cmd == 'clear_word'
        let input = substitute(input, '\S*\s*$', '', '')
      elseif cmd == 'clear_all'
        let input = ''
      elseif cmd == 'prev_item'
        let offset.value -= 1
      elseif cmd == 'next_item'
        let offset.value += 1
      elseif cmd == 'first_item'
        let offset.value = 1 - len(projects) 
      elseif cmd == 'last_item'
        let offset.value = 0
      elseif cmd == 'next_view'
        call s:NextView()
      elseif cmd == 'prev_view'
        call s:PreviousView()
      elseif cmd == 'open_project'
        call s:CloseListBuffer()
        break
      else
        let input = input.char
      endif

      let projects = s:ShowProjects(input, offset)

      redraw
      echo s:prompt_prefix.' '.input.s:prompt_suffix
    endwhile
  catch /^Vim:Interrupt$/
    call s:CloseListBuffer()
    call s:Debug('interrupt')
  endtry

  if cmd == 'open_project'
    let index = len(projects) - 1 + offset.value
    let project = projects[index]
    if s:IsValidProject(project)
      call s:OpenProject(project)
    else
      call s:Warn('Not accessible path: '.project.fullpath)
    endif
  endif
endfunction

function! s:IsValidProject(project)
  let fullpath = a:project.fullpath
  return isdirectory(fullpath) || filereadable(fullpath)
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
  let prev = s:project
  let current = a:project

  if prev != current
    if !empty(prev)
      call s:Debug('Save previous project: '.prev.name)
      call s:SaveSession()
      silent %bdelete
    endif
    let s:project = current

    call s:Info('Open project: '.s:project.name)
    call s:LoadProject()
    call s:SetEnvVariables()
    call s:SyncGlobalVariables()
    call s:SourceInitFile()
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

function! project#main#OpenProjectRoot()
  if s:IsProjectExist()
    let path = s:GetProjectRootPath()
    if !empty(path)
      execute 'edit '.path
    endif
  endif
endfunction

function! project#main#OpenProjectConfig()
  if s:IsProjectExist()
    execute 'edit '.s:config_path.s:project.name
  endif
endfunction

function! project#main#OpenPluginConfig()
  execute 'edit '.s:config_path
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
          \'note': s:project.note, 
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
  call s:OnVimLeave()
endfunction

function! s:SetStartBuffer()
  let buftype = &buftype
  let bufname = expand('%')

  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1
  let open_root = s:open_root
        \ || &buftype == 'nofile' 
        \ || bufname == '' 
        \ || is_nerdtree_tmp
  if open_root
    if is_nerdtree_tmp
      silent bdelete
    endif
    call s:Debug('Open root from buf '.bufname)
    let path = s:GetProjectRootPath()
    if !empty(path)
      if exists('g:loaded_nerd_tree')
        let edit_cmd = 'NERDTree' 
      else
        let edit_cmd = 'edit'
      endif
      execute edit_cmd.' '.path.' | silent only |  cd '.path
    else
      execute 'silent only | enew'
    endif
  endif
endfunction

function! s:GetProjectRootPath()
  let path = s:project.fullpath
  if has_key(s:project.option, 'root')
    let root = substitute(s:project.option.root, '^\.\?[/\\]', '', '')
    let path = path.'/'.root
  endif
  if isdirectory(path) || filereadable(path)
    return path
  else
    redraw
    call s:Warn('Project path not found: '.path)
    return ''
  endif
endfunction

function! s:OnVimLeave()
  augroup vim-project-leave
    autocmd! vim-project-leave
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
  let head_file = project.fullpath.'/.git/HEAD'

  if filereadable(head_file)
    let head = join(readfile(head_file), "\n")

    if !v:shell_error
      let s:branch = matchstr(head, 'refs\/heads\/\zs\w*')
    else
      call s:Warn('Error on find branch: '.v:shell_error)
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
  let head_file = s:project.fullpath.'/.git/HEAD'
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

let s:nerdtree_other = 0
let s:nerdtree_current = 0
function! s:HandleNerdtreeBefore()
  let has_nerdtree = exists('g:loaded_nerd_tree') 
        \&& g:NERDTree.IsOpen()
  if has_nerdtree
    if &filetype != 'nerdtree'
      call s:Debug('Toggle nerdtree off')
      let s:nerdtree_other = 1
      NERDTreeToggle
    else
      call s:Debug('Clear nerdtree')
      let s:nerdtree_current = 1
      let s:nerdtree_current_file = expand('%')
      setlocal filetype=
      setlocal syntax=
      execute 'file '.s:nerdtree_tmp 
    endif
  endif
endfunction

function! s:HandleNerdtreeAfter()
  if s:nerdtree_other
    let s:nerdtree_other = 0
    call s:Debug('Toggle nerdtree')
    NERDTreeToggle
    wincmd p
  endif
  if s:nerdtree_current
    let s:nerdtree_current = 0
    call s:Debug('Recover nerdtree')
    execute 'file '.s:nerdtree_current_file
    silent! setlocal filetype=nerdtree
    setlocal syntax=nerdtree
  endif
endfunction

let s:floaterm = 0
function! s:handleFloatermBefore()
  let has_floaterm = &filetype == 'floaterm'
  if has_floaterm
    let s:floaterm = 1
    FloatermToggle
  endif
endfunction

function! s:handleFloatermAfter()
  if s:floaterm
    let s:floaterm = 0
    FloatermToggle
  endif
endfunction

function! s:BeforeSaveSession()
  call s:HandleNerdtreeBefore()
endfunction

function! s:AfterSaveSession()
  call s:HandleNerdtreeAfter()
endfunction

function! s:BeforeReloadSession()
  call s:handleFloatermBefore()
endfunction

function! s:AfterReloadSession()
  call s:handleFloatermAfter()
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
    call s:BeforeReloadSession()

    call s:SaveSession()
    silent %bdelete
    let s:branch = new_branch
    let g:vim_project_branch = s:branch
    call s:LoadSession(1)
    call s:SetStartBuffer()

    call s:AfterReloadSession()
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

function! s:Warn(msg)
  echohl WarningMsg
  echom '['.s:name.'] '.a:msg
  echohl None
endfunction

function! s:Info(msg)
  echom '['.s:name.'] '.a:msg
endfunction
"}}}

" vim: fdm=marker
