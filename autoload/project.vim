if exists('g:vim_project_loaded') | finish | endif
let g:vim_project_loaded = 1

function! s:Prepare()
  let s:name = 'vim-project'
  let s:project_list_prefix = 'Open a project:'
  let s:search_files_prefix = 'Search files by name:'
  let s:laststatus_save = &laststatus
  let s:initial_length = 0
  let s:head_file_job = 0
  let s:project = {}
  let s:branch = ''
  let s:branch_default = '_'
  let s:list_buffer = '__vim_project_list__'
  let s:nerdtree_tmp = '__vim_project_nerdtree_tmp__'

  let s:add_file = 'project.add.vim'
  let s:ignore_file = 'project.ignore.vim'
  let s:init_file = 'init.vim'
  let s:quit_file = 'quit.vim'

  let s:default = {
        \'home': '~/.vim/vim-project-config',
        \'session': 0,
        \'branch': 0,
        \'open_entry': 0,
        \'auto_detect': 'always',
        \'auto_detect_file': '.git, .svn',
        \'auto_load_on_start': 0,
        \'project_base': '~',
        \'views': [],
        \'debug': 0,
        \}
  let s:default.open_file = {
        \'': 'edit',
        \'v': 'vsplit',
        \'s': 'split',
        \'t': 'tabedit',
        \}
  let s:default.project_list_mapping = {
        \'open': "\<cr>",
        \'close_list':   "\<esc>",
        \'clear_char':   ["\<bs>", "\<c-a>"],
        \'clear_word':   "\<c-w>",
        \'clear_all':    "\<c-u>",
        \'prev_item':    ["\<c-k>", "\<up>"],
        \'next_item':    ["\<c-j>", "\<down>"],
        \'first_item':   ["\<c-h>", "\<left>"],
        \'last_item':    ["\<c-l>", "\<right>"],
        \'prev_view':    "\<s-tab>",
        \'next_view':    "\<tab>",
        \}

  " Used by statusline
  let g:vim_project = {}

  let s:projects = []
  let s:projects_ignore = []
  let s:projects_error = []
endfunction


function! s:GetConfig(name, default)
  let name = 'g:vim_project_'.a:name
  let value = exists(name) ? eval(name) : a:default

  if a:name == 'config'
    let value = s:MergeUserConfigIntoDefault(value, s:default)
  endif

  return value
endfunction

function! s:MergeUserConfigIntoDefault(user, default)
  let user = a:user
  let default = a:default

  if has_key(user, 'open_file')
    let user.open_file = s:MergeUserConfigIntoDefault(
          \user.open_file,
          \default.open_file)
  endif

  if has_key(user, 'project_list_mapping')
    let user.project_list_mapping = s:MergeUserConfigIntoDefault(
          \user.project_list_mapping,
          \default.project_list_mapping)
  endif

  for key in keys(default)
    if has_key(user, key)
      let default[key] = user[key]
    endif
  endfor
  
  return default
endfunction

function! s:InitConfig()
  let s:config = s:GetConfig('config', {})
  let s:config_home = expand(s:config.home)
  let s:base = s:config.project_base
  let s:open_entry = s:config.open_entry
  let s:enable_branch = s:config.branch
  let s:enable_session = s:config.session

  " options: 'always'(default), 'ask', 'no'
  let s:auto_detect = s:config.auto_detect
  let s:auto_detect_file = s:config.auto_detect_file
  let s:auto_load_on_start = s:config.auto_load_on_start
  let s:views = s:config.views
  let s:view_index = -1
  let s:project_list_mapping = s:config.project_list_mapping
  let s:open_types = s:config.open_file
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
  let index = a:0 >1 ? a:2 : len(s:projects)

  let hasProject = s:HasProjectWithSameFullPath(
        \fullpath,
        \s:projects
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
  if !isdirectory(fullpath)
    call s:Warn('No directory: '.s:ReplaceHomeWithTide(fullpath))
    call insert(s:projects_error, project)
    return -1
  else
    call s:InitProjectConfig(project)
    call insert(s:projects, project, index)
  endif
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
        \s:projects
        \)
  if hasProject
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
  call add(s:projects_ignore, project)
endfunction

function! s:GetFullPath(path)
  let path = a:path
  let path = s:GetAbsolutePath(path)
  let path = substitute(expand(path), '\', '\/', 'g')
  let path = substitute(path, '\/$', '', '')
  return path
endfunction

function! s:IsRelativePath(path)
  let path = a:path
  let first = path[0]
  let second = path[1]
  return first != '/' && first != '~' && second != ':'
endfunction

function! s:GetAbsolutePath(path)
  let path = a:path
  if s:IsRelativePath(path)
    let base = s:base
    if base[len(base)-1] != '/'
      let base = base.'/'
    endif
    return base.path
  else
    return path
  endif
endfunction

function! s:InitProjectConfig(project)
  let name = a:project.name
  let config = s:GetProjectConfigPath(s:config_home, a:project)

  if !isdirectory(config) && exists('*mkdir')
    " Create project-specific config files
    call mkdir(config, 'p')

    " Generate init file
    let init_file = config.'/'.s:init_file
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
    let quit_file = config.'/'.s:quit_file
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

function! s:GetProjectConfigPath(config_home, project)
  let id = a:project.path
  let id = s:ReplaceHomeWithTide(id)
  let id = substitute(id, '/', '_', 'g')
  let project_folder = a:project.name.'___@'.id
  return a:config_home.'/'.project_folder
endfunction

function! project#ListProjectNames(A, L, P)
  let projects = deepcopy(s:projects)
  let names =  map(projects, {_, project -> project.name})
  let matches = filter(names, {idx, val -> val =~ a:A})
  return matches
endfunction

function! project#ListAllProjectNames(A, L, P)
  let projects = deepcopy(s:projects + s:projects_error)
  let names =  map(projects, {_, project -> project.name})
  let matches = filter(names, {idx, val -> val =~ a:A})
  return matches
endfunction

function! project#ListDirs(A, L, P)
  let head = s:GetPathHead(a:A)
  if s:IsRelativePath(a:A)
    let head = s:GetAbsolutePath(head)
    let tail = a:A
  else
    let tail = s:GetPathTail(a:A)
  endif
  let dirs = split(globpath(head, '*'), "\n")

  call filter(dirs,
        \{idx, val -> match(s:GetPathTail(val), tail) == 0})
  call filter(dirs,
        \{idx, val -> isdirectory(expand(val))})
  call map(dirs,
        \{idx, val -> s:ReplaceHomeWithTide(val)})

  if len(dirs) == 1 && isdirectory(expand(dirs[0]))
    let dirs[0] .= '/'
  endif
  return dirs
endfunction

function! s:GetPathHead(path)
  return matchstr(a:path, '.*/\ze[^/]*$')
endfunction

function! s:GetPathTail(path)
  return matchstr(a:path, '.*/\zs[^/]*$')
endfunction

" Call this entry function first
function! project#begin()
  call s:Main()
  call s:SourcePluginConfigFiles()
  call s:WatchOnBufEnter()
endfunction

function! s:SourcePluginConfigFiles()
  let add_file = s:config_home.'/'.s:add_file
  let ignore_file = s:config_home.'/'.s:ignore_file
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
  let file = s:config_home.'/'.s:add_file
  call writefile([cmd], file, 'a')
endfunction

function! s:RemoveItemInPluginConfigAdd(path)
  let target = s:ReplaceHomeWithTide(a:path)
  let target_pat = '\s'.escape(target, '~\/').'[\/]\?$'
  let file = s:config_home.'/'.s:add_file
  let adds = readfile(file)
  let idx = 0
  for line in adds
    if match(line, target_pat) != -1
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
  let file = s:config_home.'/'.s:ignore_file
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
    let project = s:GetProjectByFullpath(s:projects, buf)
    if empty(project)
      let path = s:GetPathContain(buf, s:auto_detect_file)
      if !empty(path)
        let project = s:GetProjectByFullpath(s:projects, path)
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
      let project = s:GetProjectByFullpath(s:projects, path)
      let ignore = s:GetProjectByFullpath(
            \s:projects_ignore, path)

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
  call s:PrepareListBuffer()
  let Init = function('s:ProjectListBufferInit')
  let Update = function('s:ProjectListBufferUpdate')
  let Open = function('s:ProjectListBufferOpen')
  call s:HandleInput(s:project_list_prefix, Init, Update, Open)
endfunction

function! project#SearchFiles()
  call s:PrepareListBuffer()
  let Init = function('s:SearchFilesBufferInit')
  let Update = function('s:SearchFilesBufferUpdate')
  let Open = function('s:SearchFilesBufferOpen')
  call s:HandleInput(s:search_files_prefix, Init, Update, Open)
endfunction

function! s:PrepareListBuffer()
  call s:OpenListBuffer()
  call s:SetupListBuffer()
endfunction

function! s:OpenListBuffer()
  let s:max_height = winheight(0) - 5
  let s:max_width = winwidth(0)
  let win = s:list_buffer
  let num = bufwinnr(win)
  if num == -1
    execute 'silent noautocmd botright split '.win
  else
    execute num.'wincmd w'
  endif
endfunction

function! s:CloseListBuffer()
  let &g:laststatus = s:laststatus_save
  quit
  let num = bufnr(s:list_buffer)
  if num != -1
    execute 'bwipeout! '.num 
  endif
  redraw!
  wincmd p
endfunction

function! s:SetupListBuffer()
  setlocal buftype=nofile bufhidden=delete nobuflisted
  setlocal filetype=projectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set laststatus=0
  nnoremap<buffer> <esc> :call <SID>CloseListBuffer()<cr>
  syntax match FirstColumn /^\S*/

  " highlight ItemSelected gui=reverse term=reverse cterm=reverse
  highlight! link ItemSelected CursorLine
  highlight! link SignColumn Noise
  highlight link FirstColumn Keyword
  highlight link InfoColumn Comment
  highlight link InputChar Constant

  syntax match Comment /file results\|recently opened\|more\.\.\./
  sign define selected text=> texthl=ItemSelected linehl=ItemSelected 
endfunction

function! s:UpdateInListBuffer(display, input, offset)
  " Avoid clearing other files by mistake
  if expand('%') != s:list_buffer
    return
  endif
  let display = a:display
  let input = a:input
  let offset = a:offset
  let length = len(display)
  sign unplace 9
  if length > 0
    let current = length
    if offset.value > 0
      let offset.value = 0
    elseif current + offset.value < 1
      let offset.value = 1 - current
    endif
    let current += offset.value
    if length < s:initial_length
      let current += s:initial_length - length
    endif
    execute 'sign place 9 line='.current.' name=selected'
  endif

  if length > s:max_height
    execute 'normal! '.string(current).'G'
  endif
  call s:MatchInputChars(a:input, a:offset)
endfunction

" Default 
" @input: ''
" @offset: { 'value': 0 }, range -N,...-2,-1,0
function! s:ShowInListBuffer(display, input, offset)
  " Avoid clearing other files by mistake
  if expand('%') != s:list_buffer
    return
  endif
  normal! ggdG
  let display = a:display
  let input = a:input
  let offset = a:offset
  let length = len(display)
  if length > 0
    call append(0, display)
  endif
  if input == ''
    let s:initial_length = length
  endif
  call s:ConfineHeight(length, s:initial_length, s:max_height)

  " Remove extra blank lines
  normal! Gdd
  normal! gg 
  normal! G 
endfunction

function! s:ConfineHeight(current, min, max)
  let current = a:current
  let min = a:min
  let max = a:max

  if current < min
    " Set min height
    let counts = min - current
    call append(0, repeat([''], counts))
  endif
  execute 'resize '.min
endfunction

function! s:FilterProjectsList(list, filter, origin)
  let list = a:list
  let filter = a:filter
  let origin = a:origin

  for item in list
    let item._match_type = ''
    let item._match_index = -1

    let match_index = match(item.name, filter)
    if match_index != -1
      " Prefer continous match
      if len(origin) > 1 && count(item.name, origin) == 0
        let match_index = match_index + 10
      endif
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
  call sort(list, 's:SortProjectsList')
  return list
endfunction

function! s:SortProjectsList(a1, a2)
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

function! s:FilterProjectsListName(list, filter, reverse)
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
    call s:FilterProjectsListName(a:projects, show, 0)
    call s:FilterProjectsListName(a:projects, hide, 1)
  endif
endfunction

function! s:FilterProjects(projects, filter)
  let projects = a:projects
  call s:FilterProjectsByView(projects)

  if a:filter != ''
    let filter = join(split(a:filter, '\zs'), '.*')
    call s:FilterProjectsList(projects, filter, a:filter)
  else
    call sort(projects, 's:SortInauguralProjectsList')
  endif

  return projects
endfunction

function! s:SortInauguralProjectsList(a1, a2)
  return a:a1.name < a:a2.name ? 1 : -1
endfunction

function! s:AddRightPadding(string, length)
  let string = a:string
  let padding = repeat(' ', a:length - len(string))
  let string .= padding
  return string
endfunction

function! project#OutputProjects(...)
  let filter = a:0>0 ? a:1 : ''
  let projects = s:projects
  let projects = s:FilterProjects(projects, filter)
  echo projects
endfunction

function! s:TabulateList(list, keys, max_col_width)
  let list = a:list
  let max_col_width = a:max_col_width

  " Get max width of each column
  let max = {}
  for item in list
    for key in a:keys
      let value = s:ReplaceHomeWithTide(item[key])
      let item['__'.key] = value

      if !has_key(max, key) || len(value) > max[key]
        let max[key] = len(value)
      endif
    endfor
  endfor

  " If necessary, trim value that is too long
  let max_width = 0
  for value in values(max)
    let max_width += value
  endfor
  if max_width > s:max_width
    let max = {}
    for item in list
      for key in a:keys
        let value = item['__'.key]
        if len(value) > max_col_width
          let value = value[0:max_col_width-2].'..'
          let item['__'.key] = value
        endif
        if !has_key(max, key) || len(value) > max[key]
          let max[key] = len(value)
        endif
      endfor
    endfor
  endif

  " Add right padding
  for item in list
    for key in a:keys
      let item['__'.key] = s:AddRightPadding(item['__'.key], max[key])
    endfor
  endfor
endfunction

function! s:GetProjectListCommand(char)
  let command = ''
  for [key, value] in items(s:project_list_mapping)
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

function! s:ProjectListBufferInit(input, offset)
  let max_col_width = s:max_width / 2 - 10
  call s:TabulateList(s:projects, ['name', 'path', 'note'], max_col_width)
  return s:ProjectListBufferUpdate(a:input, a:offset, 0, [])
endfunction

function! s:ProjectListBufferUpdate(input, offset, prev_input, prev_list)
  let list = s:FilterProjects(copy(s:projects), a:input)
  let display = s:GetProjectsDisplay(list)
  call s:ShowInListBuffer(display, a:input, a:offset)
  call s:UpdateInListBuffer(display, a:input, a:offset)
  return list
endfunction

function! s:ProjectListBufferOpen(project)
  let project = a:project
  if s:IsValidProject(project)
    call s:OpenProject(project)
  else
    call s:Warn('Not accessible path: '.project.fullpath)
  endif
endfunction

function! s:SortFilesList(input, a1, a2)
  let file1 = a:a1.file
  let file2 = a:a2.file
  let input = a:input
  let first = '\c'.input[0]

  let start1 = match(file1, first)
  let start2 = match(file2, first)
  if start1 != start2
    return start1 - start2
  else
    return len(file1) - len(file2)
  endif
endfunction

function! s:GetSearchFilesDisplay(list, oldfiles_len)
  let display = map(copy(a:list), function('s:GetSearchFilesDisplayRow'))
  let oldfiles_len = a:oldfiles_len

  if oldfiles_len > 0
    let display_len = len(display)
    let display[display_len - 1] .= '  recently opened'
    if display_len > oldfiles_len
      let display[display_len - oldfiles_len - 1] .= '  file results'
    endif
  endif
  if len(a:list) > 0 && has_key(a:list[0], 'more') && a:list[0].more
    let display[0] .= '  more...'
  endif
  return display
endfunction

function! s:GetSearchFilesDisplayRow(idx, value)
  let value = a:value
  return value.__file.'  '.value.__path
endfunction

function! s:GetSearchFilesByOldFiles(dir)
  let oldfiles = copy(v:oldfiles)
  for buf in getbufinfo({'buflisted': 1})
    if count(oldfiles, s:ReplaceHomeWithTide(buf.name)) == 0
      call insert(oldfiles, buf.name)
    endif
  endfor

  call map(oldfiles, {_, val -> fnamemodify(val, ':p')})
  call filter(oldfiles, {_, val -> 
        \count(val, a:dir) > 0
        \ && count(['ControlP', ''], fnamemodify(val, ':t')) == 0
        \ && (filereadable(val) || isdirectory(val))
        \})
  call map(oldfiles, {_, val -> substitute(val, a:dir, './', '')})
  return reverse(oldfiles)
endfunction

function! s:GetFindResult(dir, filter)
  let ignore = '\( -name .git -o -name node_modules \) -prune -false -o '
  let cmd = 'cd '.a:dir.' && find . -mindepth 1 '.ignore.a:filter
  let result = split(system(cmd), '\n')
  return result
endfunction

function! s:GetSearchFilesByFind(dir, input)
  let dir = a:dir
  let input = a:input
  if empty(a:input)
    let filter = '-iname "*"'
    let list = s:GetFindResult(dir, filter)
  else
    let filter = '-iname "*'. join(split(input, '\zs'), '*').'*"'
    let list = s:GetFindResult(dir, filter)
  endif
  return list
endfunction

function! s:GetSearchFiles(dir, input)
  let input = a:input
  let oldfiles = s:GetSearchFilesByOldFiles(a:dir)
  let list = s:GetSearchFilesByFind(a:dir, input)

  call s:MapAndSortSearchFiles(list, input)
  call s:MapAndSortSearchFiles(oldfiles, input)
  call filter(oldfiles, {_, val ->
        \val.file =~ join(split(input, '\zs'), '.*')})

  let list = oldfiles + list

  let show_length = s:max_height - 1
  let current_length = len(list)

  let list = list[0:show_length*2]
  call s:UniqueList(list)
  let list = list[0:show_length]

  if current_length >= s:max_height
    let list[len(list)-1].more = 1
  endif

  call reverse(list)
  return [list, oldfiles]
endfunction

function! s:MapAndSortSearchFiles(list, input)
  let list = a:list
  let input = a:input
  call map(list, {idx, val -> 
        \{ 
        \'file': fnamemodify(val, ':t'), 
        \'path': fnamemodify(val, ':h:s+\./\?++'),
        \}})
  if !empty(input)
    call sort(list, function('s:SortFilesList', [input]))
  endif
endfunction

function! s:SearchFilesBufferInit(input, offset)
  return s:SearchFilesBufferUpdate(a:input, a:offset, '', '')
endfunction

function! s:SearchFilesBufferUpdate(input, offset, prev_input, prev_list)
  if empty(a:input) || a:input != a:prev_input
    let dir = fnamemodify($vim_project, ':p')
    let [list, oldfiles] = s:GetSearchFiles(dir, a:input)
    let max_col_width = s:max_width / 2 - 12
    call s:TabulateList(list, ['file', 'path'], max_col_width)
    let display = s:GetSearchFilesDisplay(list, len(oldfiles))
    call s:ShowInListBuffer(display, a:input, a:offset)
    call s:UpdateInListBuffer(display, a:input, a:offset)
    return list
  else
    call s:UpdateInListBuffer(a:prev_list, a:input, a:offset)
    return a:prev_list
  endif
endfunction

function! s:SearchFilesBufferOpen(target)
  let file = $vim_project.'/'.a:target.path.'/'.a:target.file
  execute 'edit '.file
endfunction

function! s:HandleInput(prefix, Init, Update, Open)
  " Init
  let input = ''
  let prev_input = ''
  let offset = { 'value': 0 }
  let list = a:Init(input, offset)
  let prev_list = list
  redraw
  echo a:prefix.' '

  try
    while 1
      let c = getchar()
      let char = type(c) == v:t_string ? c : nr2char(c)
      let cmd = s:GetProjectListCommand(char)
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
        let offset.value = 1 - len(list) 
      elseif cmd == 'last_item'
        let offset.value = 0
      elseif cmd == 'next_view'
        call s:NextView()
      elseif cmd == 'prev_view'
        call s:PreviousView()
      elseif cmd == 'open'
        call s:CloseListBuffer()
        break
      else
        let input = input.char
      endif

      let list = a:Update(input, offset, prev_input, prev_list)
      let prev_input = input
      let prev_list = list
      redraw
      echo a:prefix.' '.input
    endwhile
  catch /^Vim:Interrupt$/
    call s:CloseListBuffer()
    call s:Debug('Interrupt')
  endtry

  if cmd == 'open'
    let index = len(list) - 1 + offset.value
    let target = list[index]
    call a:Open(target)
  endif
endfunction

function! s:IsValidProject(project)
  let fullpath = a:project.fullpath
  return isdirectory(fullpath) || filereadable(fullpath)
endfunction

function! s:GetProjectByName(name, projects)
  for project in a:projects
    if project.name == a:name
      return project
    endif
  endfor

  return {}
endfunction

function! project#OpenProjectByName(name)
  let project = s:GetProjectByName(a:name, s:projects)
  if !empty(project)
    call s:OpenProject(project)
  else
    call s:Warn('Project not found: '.a:name)
  endif
endfunction

function! project#RemoveProjectByName(name)
  let project = s:GetProjectByName(a:name, s:projects)
  if empty(project)
    let project = s:GetProjectByName(a:name, s:projects_error)
  endif

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
  let target = a:project
  let projects = s:projects

  if target == s:project
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
  let $vim_project_config =
        \s:GetProjectConfigPath(s:config_home, s:project)
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
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    execute 'edit '.config
  endif
endfunction

function! project#OpenAllConfig()
  execute 'edit '.s:config_home
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
  let config = s:GetProjectConfigPath(s:config_home, s:project)
  let file = config.'/'.a:file
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
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    return config.'/sessions'
  else
    return ''
  endif
endfunction


function! s:GetSessionFile()
  if s:IsProjectExist()
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    return config.'/sessions/'.s:branch.'.vim'
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

function! s:GetProjectsDisplay(list)
  return map(copy(a:list), function('s:GetProjectsDisplayRow'))
endfunction

function! s:GetProjectsDisplayRow(key, value)
  let value = a:value
  return value.__name.'  '
        \.value.__note.'  '
        \.s:ReplaceHomeWithTide(value.__path)
endfunction

function! project#MapFile(config)
  let config = a:config
  if has_key(config, 'direct')
    call s:MapDirectFile(config.direct)
  endif

  if has_key(config, 'link')
    call s:MapLinkedFile(config.link)
  endif

  if has_key(config, 'custom')
    call s:MapCustomFile(config.custom)
  endif
endfunction

function! s:MapDirectFile(direct)
  let index = 0
  for key in a:direct.key
    let file = a:direct.file[index]
    for [open_key, open_type] in items(s:open_types)
      execute "nnoremap '".open_key.key.' :update<cr>'
            \.':call <SID>OpenFile("'.open_type.'", "'.file.'")<cr>'
    endfor
    let index += 1
  endfor
endfunction

function! s:MapLinkedFile(link)
  if len(a:link.file) == 2
    let s:GotoLinked =
          \function('s:GotoLinkedFile', [a:link])
    for [open_key, open_type] in items(s:open_types)
      execute "nnoremap '".open_key.a:link.key
            \.' :update<cr>:call <SID>GotoLinked("'.open_type.'")<cr>'
    endfor
  endif
endfunction

function! s:MapCustomFile(custom)
  let s:CustomFuncRef = a:custom.file
  " It seems that only function... can be called by <SID> in map
  function! s:CustomFunc()
    return s:CustomFuncRef()
  endfunction

  for [open_key, open_type] in items(s:open_types)
    let sid = expand('<SID>')
    execute "nnoremap '".open_key.a:custom.key
          \.' :update<cr>'
          \.' :call <SID>OpenFile("'.open_type.'", '.sid.'CustomFunc())<cr>'
  endfor
endfunction

function! s:GotoLinkedFile(link, open_type)
  let linked_files = a:link.file
  let current_index = index(linked_files, expand('%:e'))
  
  if current_index != -1 " By file extension
    let target =  expand('%:p:r').'.'.linked_files[1 - current_index]
  else " By specific file, default to first one
    let current_file = substitute(expand('%:p'), $vim_project.'/', '', '')
    let current_index = index(linked_files, current_file)
    if current_index != -1
      let target = linked_files[1 - current_index]
    elseif linked_files[0] !~ '^\w*$'
      let target = linked_files[0]
    endif
  endif
  if exists('target')
    call s:OpenFile(a:open_type, target)
  endif
endfunction

function! s:OpenFile(open_type, target)
  let target = a:target
  if s:IsRelativePath(target)
    let target = $vim_project.'/'.target
  endif
  execute a:open_type.' '.expand(target)
endfunction

function! s:MatchInputChars(input, offset)
  call clearmatches()
  let lastline = line('$')
  let current = lastline + a:offset.value
  for lnum in range(1, lastline)
    " if lnum != current
      let pos = s:GetMatchPos(lnum, a:input)
      if len(pos) > 0
        for i in range(0, len(pos), 8)
          call matchaddpos('InputChar', pos[i:i+7])
        endfor
      endif
    " endif
  endfor
endfunction

function! s:GetMatchPos(lnum, input)
  let line = split(matchstr(getline(a:lnum), '^\S*'), '\zs')
  let search = split(a:input, '\zs')
  let pos = []
  let start = 0
  for char in search
    let start = index(line, char, start, 1) + 1
    if start == 0
      break
    endif

    call add(pos, [a:lnum, start])
  endfor
  return pos
endfunction

function! s:UniqueList(list)
  let compare = copy(a:list)
  call filter(a:list, function('s:UniqueListByFile', [compare]))
endfunction

function! s:UniqueListByFile(list, idx, val)
  for i in range(0, a:idx - 1)
    let item = a:list[i]
    if item.file == a:val.file && item.path == a:val.path
      return 0
    endif
  endfor
  return 1
endfunction

function! s:Main()
  call s:Prepare()
  call s:InitConfig()
endfunction
