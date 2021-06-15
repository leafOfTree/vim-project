if exists('g:vim_project_loaded') | finish | endif
let g:vim_project_loaded = 1

function! s:Prepare()
  let s:name = 'vim-project'
  let s:prompt_prefix = 'Open a project:'
  let s:laststatus_save = &laststatus
  let s:origin_height = 0
  let s:head_file_job = 0
  let s:project = {}
  let s:branch = ''
  let s:branch_default = '_'
  let s:list_buffer = '__projects__'
  let s:nerdtree_tmp = '__vim_project_nerdtree_tmp__'
  let s:format_cache = 0

  let s:base = '~/'
  let s:add_file = 'project.add.vim'
  let s:ignore_file = 'project.ignore.vim'
  let s:init_file = 'init.vim'
  let s:quit_file = 'quit.vim'

  let s:prompt_mapping_default = {
        \'open_project': "\<cr>",
        \'close_list': "\<esc>",
        \'clear_char': ["\<bs>", "\<c-a>"],
        \'clear_word': "\<c-w>",
        \'clear_all': "\<c-u>",
        \'prev_item': ["\<c-k>", "\<up>"],
        \'next_item': ["\<c-j>", "\<down>"],
        \'first_item': ["\<c-h>", "\<left>"],
        \'last_item': ["\<c-l>", "\<right>"],
        \'prev_view': "\<s-tab>",
        \'next_view': "\<tab>",
        \}

  let s:default = {
        \'config_path': '~/.vim',
        \'session': 0,
        \'branch': 0,
        \'open_entry': 0,
        \'auto_detect': 'always',
        \'auto_detect_file': '.git, .svn, package.json, pom.xml, Gemfile',
        \'auto_load_on_start': 0,
        \'prompt_mapping': s:prompt_mapping_default,
        \'views': [],
        \'debug': 0,
        \}

  " Used by statusline
  let g:vim_project = {}

  let g:vim_project_projects = []
  let g:vim_project_projects_ignore = []
endfunction


function! s:GetConfig(name, default)
  let name = 'g:vim_project_'.a:name
  let value = exists(name) ? eval(name) : a:default

  if a:name == 'config'
    let value = s:MergeUserConfigIntoDefault(value)
  endif

  return value
endfunction

function! s:MergeUserConfigIntoDefault(user)
  let user = a:user
  let default = s:default

  if has_key(user, 'prompt_mapping')
    let user.prompt_mapping = 
          \ s:MergeUserMappingIntoDefault(user.prompt_mapping)
  endif

  for key in keys(default)
    if has_key(user, key)
      let default[key] = user[key]
    endif
  endfor
  
  let default.config_path = s:GetConfigPath(default.config_path)
  return default
endfunction

function! s:GetConfigPath(prefix)
  let prefix = a:prefix
  if prefix[len(prefix)-1] != '/'
    let prefix = prefix.'/'
  endif
  return expand(prefix.s:name.'-config/')
endfunction

function! s:MergeUserMappingIntoDefault(user)
  let user = a:user
  let default = s:prompt_mapping_default
  for key in keys(default)
    if has_key(user, key)
      let default[key] = user[key]
    endif
  endfor
  return default
endfunction

function! s:InitConfig()
  let s:config = s:GetConfig('config', {})
  let s:config_path = s:config.config_path
  let s:open_entry = s:config.open_entry
  let s:enable_branch = s:config.branch
  let s:enable_session = s:config.session

  " options: 'always'(default), 'ask', 'no'
  let s:auto_detect = s:config.auto_detect
  let s:auto_detect_file = s:config.auto_detect_file
  let s:auto_load_on_start = s:config.auto_load_on_start
  let s:views = s:config.views
  let s:view_index = -1
  let s:prompt_mapping = s:config.prompt_mapping
  let s:debug = s:config.debug
endfunction

function! project#SetBase(base)
  let s:base = a:base
endfunction

function! s:GetAddArgs(args)
  let args = split(a:args, ',\s*\ze{')
  let path = args[0]
  let option = len(args) > 1 ? js_decode(args[1]) : {}
  return [path, option]
endfunction

function! project#AddProject(args)
  let [path, option] = s:GetAddArgs(a:args)
  let error = s:AddProject(path, option)
  if !error && !s:sourcing_file
    let save_path = s:ReplaceHomeWithTide(s:GetFullPath(path))
    call s:SaveToPluginConfigAdd(save_path)
    redraw
    call s:InfoHl('Added: '.path)
  endif
endfunction

function! s:AddProject(path, ...)
  let fullpath = s:GetFullPath(a:path)
  let option = a:0 > 0 ? a:1 : {}
  let index = a:0 >1 ? a:2 : len(g:vim_project_projects)

  if !isdirectory(fullpath)
    call s:Warn('No directory: '.s:ReplaceHomeWithTide(fullpath))
    return -1
  endif
  let hasProject = s:HasProjectWithSameFullPath(
        \fullpath,
        \g:vim_project_projects
        \)
  if hasProject
    call s:Info('Already have it')
    return -1
  endif

  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  let note = get(option, 'note', '')

  " fullpath: with project name
  " path: without project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': fullpath,
        \'note': note, 
        \'option': option,
        \}
  call s:InitProjectConfig(project)
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

function! project#IgnoreProject(path)
  let path = s:ReplaceHomeWithTide(a:path)
  let error = s:IgnoreProject(path)
  if !error && !s:sourcing_file
    call s:SaveToPluginConfigIgnore(path)
    redraw
    call s:InfoHl('Ignored '.path)
  endif
endfunction

function! s:ReplaceHomeWithTide(path)
  return substitute(a:path, '^'.expand('~'), '~', '')
endfunction

" Ignore path for auto adding
function! s:IgnoreProject(path)
  let fullpath = s:GetFullPath(a:path)
  let hasProject = s:HasProjectWithSameFullPath(
        \fullpath,
        \g:vim_project_projects
        \)
  if hasProject
    call s:Debug('Already ignored '.fullpath)
    return -1
  endif

  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  " path: with project name
  " fullpath: no project name
  let project = { 
        \'name': name, 
        \'path': path, 
        \'fullpath': fullpath,
        \}
  call add(g:vim_project_projects_ignore, project)
endfunction

function! s:GetFullPath(path)
  let path = a:path
  if path[0] != '/' && path[0] != '~' && path[1] != ':'
    let path = s:GetAbsolutePath(path)
  endif
  let path = substitute(expand(path), '\', '\/', 'g')
  let path = substitute(path, '\/$', '', '')
  return path
endfunction

function! s:GetAbsolutePath(path)
  let base = s:base
  if base[len(base)-1] != '/'
    let base = base.'/'
  endif
  return base.a:path
endfunction

function! s:InitProjectConfig(project)
  let name = a:project.name
  let config_path = s:GetProjectConfigPath(s:config_path, a:project)

  if !isdirectory(config_path) && exists('*mkdir')
    " Create project-specific config files
    call mkdir(config_path, 'p')

    " Generate init file
    let init_file = config_path.'/'.s:init_file
    let init_content = [
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'" When: sourced after session is loaded',
          \'" Project: '.name, 
          \'" Variable: $vim_project, $vim_project_config',
          \'" Example: open `./src` on start',
          \'" - edit $vim_project/src',
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \]
    call writefile(init_content, init_file)

    " Generate quit file
    let quit_file = config_path.'/'.s:quit_file
    let quit_content = [
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'" When: sourced after session is saved',
          \'" Project: '.name, 
          \'" Variable: $vim_project, $vim_project_config',
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
  echohl Statement | echom '['.s:name.'] ' | echohl None | echon a:msg
endfunction

function! s:GetProjectConfigPath(config_path, project)
  let id = substitute(a:project.path, '/', '_', 'g')
  let folder = a:project.name.'__'.id
  return a:config_path.folder
endfunction

function! project#ListProjectNames(A, L, P)
  let projects = deepcopy(g:vim_project_projects)
  let names =  map(projects, {_, project -> "'".project.name."'"})
  let matches = filter(names, {idx, val -> val =~ a:A})
  return matches
endfunction

" Call this entry function first
function! project#begin()
  call s:Main()
  call s:SourcePluginConfigFiles()
  call s:WatchOnBufEnter()
endfunction

function! s:SourcePluginConfigFiles()
  let add_file = s:config_path.'/'.s:add_file
  let ignore_file = s:config_path.'/'.s:ignore_file
  let s:sourcing_file = 1
  if filereadable(add_file)
    execute 'source '.add_file
  endif
  if filereadable(ignore_file)
    execute 'source '.ignore_file
  endif
  let s:sourcing_file = 0
endfunction

function! s:SaveToPluginConfigAdd(path)
  let cmd = 'ProjectAdd '.a:path
  let file = s:config_path.'/'.s:add_file
  call writefile([cmd], file, 'a')
endfunction

function! s:RemoveItemInPluginConfigAdd(path)
  let target = s:ReplaceHomeWithTide(a:path)
  let file = s:config_path.'/'.s:add_file
  let adds = readfile(file)
  let idx = 0
  for line in adds
    if count(line, target)
      break
    endif
    let idx += 1 
  endfor
  if idx < len(adds)
    call remove(adds, idx)
    call writefile(adds, file)
  endif
endfunction

function! s:SaveToPluginConfigIgnore(path)
  let file = s:config_path.'/'.s:ignore_file
  let cmd = 'ProjectIgnore '.a:path
  call writefile([cmd], file, 'a')
endfunction

function! s:WatchOnBufEnter()
  augroup vim-project-enter
    autocmd! vim-project-enter
    if s:auto_load_on_start
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
      let path = s:GetPathContain(buf, s:auto_detect_file)
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
    execute 'ProjectOpen '.project.name

    if project.fullpath is s:startup_buf
      " Follow session files if open the entry path
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
    let path = s:GetPathContain(buf, s:auto_detect_file)
    if !empty(path)
      let project = s:GetProjectByFullpath(g:vim_project_projects, path)
      let ignore = s:GetProjectByFullpath(
            \g:vim_project_projects_ignore, path)

      if empty(project) && empty(ignore)
        let path = s:ReplaceHomeWithTide(path)
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
  call s:AddProject(a:path, {})
  call s:SaveToPluginConfigAdd(a:path)
  redraw
  call s:InfoHl('Added: '.a:path)
endfunction

function! s:AutoIgnoreProject(path)
  call s:IgnoreProject(a:path)
  call s:SaveToPluginConfigIgnore(a:path)
  redraw
  call s:InfoHl('Ignored '.a:path)
endfunction

function! s:GetPathContain(buf, pat)
  let segments = split(a:buf, '/\|\\', 1)
  let depth = len(segments)
  let pats = split(a:pat, ',\s*')

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

function! s:Warn(msg)
  echohl WarningMsg
  echom '['.s:name.'] '.a:msg
  echohl None
endfunction

function! project#ListProjects()
  call s:OpenListBuffer()
  call s:SetupListBuffer()
  call s:HandleInput()
endfunction

function! s:OpenListBuffer()
  let win = s:list_buffer
  let num = bufwinnr(win)
  if num == -1
    execute 'noautocmd botright split '.win
  else
    execute num.'wincmd w'
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
        \copy(s:GetAllProjects()),
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
    let filter = join(split(a:filter, '\zs'), '.*')
    call s:FilterList(projects, filter)
  else
    call sort(projects, 's:SortInauguralList')
  endif

  return projects
endfunction

function! s:SortInauguralList(a1, a2)
  return a:a1.name < a:a2.name ? 1 : -1
endfunction

function! s:AddRightPadding(string, length)
  let padding = repeat(' ', a:length - len(a:string))
  return a:string.padding
endfunction

function! s:GetAllProjects()
  let projects = exists('g:vim_project_projects')
        \ ? g:vim_project_projects
        \ : []
  return projects
endfunction

function! project#OutputProjects(...)
  let filter = a:0>0 ? a:1 : ''
  let projects = s:GetAllProjects()
  let projects = s:FilterProjects(projects, filter)
  echo projects
endfunction

function! s:FormatProjects()
  let list = s:GetAllProjects()
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
  echo s:prompt_prefix.' '

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
      echo s:prompt_prefix.' '.input
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
  let projects = s:GetAllProjects()
  for project in projects
    if project.name == a:name
      return project
    endif
  endfor

  return {}
endfunction

function! project#OpenProjectByName(name)
  let project = s:GetProjectByName(a:name)
  if !empty(project)
    call s:OpenProject(project)
  else
    call s:Warn('Project not found: '.a:name)
  endif
endfunction

function! project#RemoveProjectByName(name)
  let project = s:GetProjectByName(a:name)
  if !empty(project)
    call s:RemoveProject(project)
  else
    call s:Warn('Project not found: '.a:name)
  endif
endfunction

function! s:OpenProject(project)
  let prev = s:project
  let current = a:project

  if prev != current
    if !empty(prev)
      call s:Debug('Save previous project: '.prev.name)
      call s:SaveSession()
      silent! %bdelete
    endif
    let s:project = current

    call s:LoadProject()
    call s:SetEnvVariables()
    call s:SyncGlobalVariables()
    call s:SourceInitFile()

    redraw
    call s:Info('Open: '.s:project.name)
  else
    call s:Info('Already opened')
  endif
endfunction

function! s:RemoveProject(project)
  let current = s:project
  let target = a:project
  let projects = s:GetAllProjects()

  if target == current
    ProjectQuit
  endif

  let idx = index(projects, target)
  call remove(projects, idx)
  call s:Info('Removed: '. target.name)
  call s:SaveToPluginConfigIgnore(target.fullpath)
  call s:RemoveItemInPluginConfigAdd(target.fullpath)
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

function! project#OpenProjectEntry()
  if s:IsProjectExist()
    let path = s:GetProjectEntryPath()
    if !empty(path)
      execute 'edit '.path
    endif
  endif
endfunction

function! project#OpenProjectConfig()
  if s:IsProjectExist()
    let config_path = s:GetProjectConfigPath(
          \s:config_path, s:project)
    execute 'edit '.config_path
  endif
endfunction

function! project#OpenTotalConfig()
  execute 'edit '.s:config_path
endfunction

function! project#QuitProject()
  if s:IsProjectExist()
    call s:Info('Quit: '.s:project.name)
    call s:SaveSession()
    call s:SourceQuitFile()

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
          \'option': s:project.option,
          \'branch': s:branch,
          \}
  else
    let g:vim_project = {}
  endif
endfunction

function! project#ShowProjectInfo()
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
  call s:StartWatchJob()
  call s:SetStartBuffer()
  call s:OnVimLeave()
endfunction

function! s:SetStartBuffer()
  let buftype = &buftype
  let bufname = expand('%')

  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1
  let open_entry = s:open_entry
        \ || &buftype == 'nofile' 
        \ || bufname == '' 
        \ || is_nerdtree_tmp
  let path = s:GetProjectEntryPath()
  if open_entry
    if is_nerdtree_tmp
      silent bdelete
    endif
    call s:Debug('Open entry'.(bufname ? ' from buf '.bufname : ''))
    if !empty(path)
      if isdirectory(path)
        if exists('g:loaded_nerd_tree')
          let edit_cmd = 'NERDTree' 
        else
          let edit_cmd = 'edit'
        endif
        execute edit_cmd.' '.path.' | silent only |  cd '.path
      else
        execute 'edit '.path
      endif
    else
      execute 'silent only | enew'
    endif
  else
    execute 'cd '.path
  endif
endfunction

function! s:GetProjectEntryPath()
  let path = s:project.fullpath
  if has_key(s:project.option, 'entry')
    " Remove the relative part './'
    let entry = substitute(s:project.option.entry, '^\.\?[/\\]', '', '')
    let path = path.'/'.entry
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
    autocmd VimLeavePre * call project#QuitProject()
  augroup END
endfunction

function! s:SourceInitFile()
  call s:SourceFile(s:init_file)
endfunction

function! s:SourceQuitFile()
  call s:SourceFile(s:quit_file)
endfunction

function! s:SourceFile(file)
  let name = s:project.name.'-'.s:project.path
  let config_path = s:GetProjectConfigPath(s:config_path, s:project)
  let file = config_path.'/'.a:file
  if filereadable(file)
    call s:Debug('Source file: '.file)
    execute 'source '.file
  else
    call s:Debug('Not found file: '.file)
  endif
endfunction

function! s:FindBranch(...)
  if !s:enable_branch
    let s:branch = s:branch_default
    return
  endif

  let project = a:0>0 ? a:1 : s:project
  let head_file = project.fullpath.'/.git/HEAD'

  if filereadable(head_file)
    let head = join(readfile(head_file), "\n")

    if !v:shell_error
      let s:branch = matchstr(head, 'refs\/heads\/\zs.*')
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

function! s:GetSessionFolder()
  if s:IsProjectExist()
    let config_path = s:GetProjectConfigPath(s:config_path, s:project)
    return config_path.'/sessions'
  else
    return ''
  endif
endfunction


function! s:GetSessionFile()
  if s:IsProjectExist()
    let config_path = s:GetProjectConfigPath(s:config_path, s:project)
    return config_path.'/sessions/'.s:branch.'.vim'
  else
    return ''
  endif
endfunction

function! s:LoadSession()
  if !s:enable_session
    return
  endif

  let file = s:GetSessionFile()
  if filereadable(file)
    call s:Debug('Load session file: '.file)
    execute 'source '.file
  else
    call s:Debug('Not session file found: '.file)
  endif
endfunction

function! s:StartWatchJob()
  let should_watch = s:enable_branch && executable('tail') == 1
  if should_watch
    let cmd = s:GetWatchCmd()
    if !empty(cmd)
      if exists('*job_start')
        call s:WatchHeadFileVim(cmd)
      elseif exists('*jobstart')
        call s:WatchHeadFileNeoVim(cmd)
      endif
    endif
  endif
endfunction

function! s:GetWatchCmd()
  let head_file = s:project.fullpath.'/.git/HEAD'
  if filereadable(head_file)
    call s:Debug('Watching .git head file: '.head_file)
    let cmd = 'tail -n0 -F '.head_file
    return cmd
  else
    return ''
  endif
endfunction

function! s:WatchHeadFileVim(cmd)
  if type(s:head_file_job) == v:t_job
    call job_stop(s:head_file_job)
  endif
  let s:head_file_job = job_start(a:cmd, 
        \ { 'callback': 'ReloadSession' })
endfunction

function! s:WatchHeadFileNeoVim(cmd)
  if s:head_file_job 
    call jobstop(s:head_file_job)
  endif
  let s:head_file_job = jobstart(a:cmd, 
        \ { 'on_stdout': 'ReloadSession' })
endfunction

function! s:SaveSession()
  if !s:enable_session
    return
  endif

  if s:IsProjectExist()
    call s:BeforeSaveSession()

    let folder = s:GetSessionFolder()
    if !isdirectory(folder) && exists('*mkdir')
      call mkdir(folder, 'p')
    endif

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

  let new_branch = matchstr(msg, 'refs\/heads\/\zs.*')
  if !empty(new_branch) && new_branch != s:branch
    call s:Info('Change branch and reload: '.new_branch)
    call s:BeforeReloadSession()

    call s:SaveSession()
    silent! %bdelete
    let s:branch = new_branch
    let g:vim_project.branch = s:branch
    call s:LoadSession()
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
  let home = expand('~')
  return value.__name.'  '
        \.value.__note.'  '
        \.s:ReplaceHomeWithTide(value.__path)
endfunction

function! s:Main()
  call s:Prepare()
  call s:InitConfig()
endfunction
