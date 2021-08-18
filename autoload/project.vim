if exists('g:vim_project_loaded') | finish | endif
let g:vim_project_loaded = 1

function! s:Prepare()
  let s:name = 'vim-project'
  let s:project_list_prefix = 'Open a project:'
  let s:search_files_prefix = 'Search files by name:'
  let s:find_in_files_prefix = 'Find in files:'
  let s:search_replace_separator = ' >>>>>> '
  let s:find_in_files_max = 200
  let s:find_in_files_to_stop_max = 100000
  let s:list_history = {}
  let s:laststatus_save = &laststatus
  let s:initial_height = 0
  let s:head_file_job = 0
  let s:project = {}
  let s:branch = ''
  let s:branch_default = '_'
  let s:reloading_project = 0
  let s:start_project = {}
  let s:start_buf = ''
  let s:dismissed_find_replace = 0
  let s:update_timer = 0
  let s:list_buffer = '__vim_project_list__'
  let s:nerdtree_tmp = '__vim_project_nerdtree_tmp__'

  let s:add_file = 'project.add.vim'
  let s:ignore_file = 'project.ignore.vim'
  let s:init_file = 'init.vim'
  let s:quit_file = 'quit.vim'

  let s:default = {
        \'config_home': '~/.vim/vim-project-config',
        \'project_base': ['~'],
        \'use_session': 0,
        \'open_entry_when_use_session': 0,
        \'check_branch_when_use_session': 0,
        \'project_entry': './',
        \'auto_detect': 'no',
        \'auto_detect_file': ['.git', '.svn'],
        \'auto_load_on_start': 0,
        \'search_include': ['./'],
        \'search_exclude': ['.git', 'node_modules'],
        \'find_in_files_include': ['./'],
        \'find_in_files_exclude': ['.git', 'node_modules'],
        \'views': [],
        \'debug': 0,
        \}
  let s:local_config_keys = [
        \'search_include',
        \'search_exclude',
        \'find_in_files_include',
        \'find_in_files_exclude',
        \'use_session',
        \'project_entry',
        \'open_entry_when_use_session',
        \'check_branch_when_use_session',
        \]
  let s:default.list_map = {
        \'open':             "\<cr>",
        \'open_split':       "\<c-s>",
        \'open_vsplit':      "\<c-v>",
        \'open_tabedit':     "\<c-t>",
        \'close_list':       "\<esc>",
        \'clear_char':       ["\<bs>", "\<c-a>"],
        \'clear_word':       "\<c-w>",
        \'clear_all':        "\<c-u>",
        \'prev_item':        ["\<c-k>", "\<up>"],
        \'next_item':        ["\<c-j>", "\<down>"],
        \'first_item':       ["\<c-h>", "\<left>"],
        \'last_item':        ["\<c-l>", "\<right>"],
        \'scroll_up':        "\<c-p>",
        \'scroll_down':      "\<c-n>",
        \'prev_view':        "\<s-tab>",
        \'next_view':        "\<tab>",
        \'replace_prompt':   "\<c-r>",
        \'replace_dismiss':  "\<c-d>",
        \'replace_confirm':  "\<c-y>",
        \'switch_to_list':   "\<c-o>",
        \}
  let s:default.file_open_types = {
        \'':  'edit',
        \'s': 'split',
        \'v': 'vsplit',
        \'t': 'tabedit',
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

  if has_key(user, 'file_open_types')
    let user.file_open_types = s:MergeUserConfigIntoDefault(
          \user.file_open_types,
          \default.file_open_types)
  endif

  if has_key(user, 'list_map')
    let user.list_map = s:MergeUserConfigIntoDefault(
          \user.list_map,
          \default.list_map)
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
  let s:config_home = expand(s:config.config_home)
  let s:open_entry_when_use_session =
        \s:config.open_entry_when_use_session
  let s:check_branch_when_use_session =
        \s:config.check_branch_when_use_session
  let s:use_session = s:config.use_session
  let s:project_entry = s:config.project_entry
  let s:project_base = s:RemoveTrailingSlash(s:config.project_base)
  let s:search_include = s:config.search_include
  let s:search_exclude = s:config.search_exclude
  let s:find_in_files_include = s:config.find_in_files_include
  let s:find_in_files_exclude = s:config.find_in_files_exclude

  " options: 'always', 'ask', 'no'
  let s:auto_detect = s:config.auto_detect
  let s:auto_detect_file = s:config.auto_detect_file
  let s:auto_load_on_start = s:config.auto_load_on_start
  let s:views = s:config.views
  let s:view_index = -1
  let s:list_map = s:config.list_map
  let s:open_types = s:config.file_open_types
  let s:debug = s:config.debug
endfunction

function! s:AdjustConfig()
  let s:search_include = s:AdjustIncludeExcludePath(s:search_include, ['.'])
  let s:search_exclude = s:AdjustIncludeExcludePath(s:search_exclude, [])
  let s:find_in_files_include =
        \s:AdjustIncludeExcludePath(s:find_in_files_include, [])
  let s:find_in_files_exclude =
        \s:AdjustIncludeExcludePath(s:find_in_files_exclude, [])
endfunction

function! s:RemoveTrailingSlash(list)
  call map(a:list, {_, val -> substitute(val, '[\/]$', '', '')})
  return a:list
endfunction

function! s:RemoveHeadingDotSlash(list)
  call map(a:list, {_, val -> substitute(val, '^\.[\/]', '', '')})
  return a:list
endfunction

function! s:AdjustIncludeExcludePath(paths, default)
  let paths = a:paths
  if empty(paths)
    let paths = a:default
  endif
  call s:RemoveTrailingSlash(paths)
  call s:RemoveHeadingDotSlash(paths)
  return paths
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

  let hasProject = s:ProjectExistsWithSameFullPath(
        \fullpath,
        \s:projects
        \)
  if hasProject
    call s:Info('Already have '.a:path)
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
    call s:Warn('No directory found: '.s:ReplaceHomeWithTide(fullpath))
    call insert(s:projects_error, project)
    return -1
  else
    call s:InitProjectConfig(project)
    call add(s:projects, project)
  endif
endfunction

function! s:ProjectExistsWithSameFullPath(fullpath, projects)
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

function! s:RemoveProjectPath(path)
  let result = substitute(a:path, $vim_project, '', '')
  let result = substitute(result, '^/', '', '')
  return result
endfunction

" Ignore path for auto adding
function! s:IgnoreProject(path)
  let fullpath = s:GetFullPath(a:path)
  let hasProject = s:ProjectExistsWithSameFullPath(
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
    for base in s:project_base
      let full_path = base.'/'.path
      if isdirectory(expand(full_path))
        return full_path
      endif
    endfor
  endif
  return path
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
          \'" Project:      '.name,
          \'" When:         after session is loaded',
          \'" Variables:    $vim_project, $vim_project_config',
          \'" Example:      to open `./src` on start',
          \'" - edit $vim_project/src',
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \]
    call writefile(init_content, init_file)

    " Generate quit file
    let quit_file = config.'/'.s:quit_file
    let quit_content = [
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'" Project name: '.name,
          \'" When:         after session is saved',
          \'" Variables:    $vim_project, $vim_project_config',
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

function! s:EchoInfo(msg)
  echo '['.s:name.'] '.a:msg
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

function! project#ListDirs(path, L, P)
  let head = s:GetPathHead(a:path)
  if s:IsRelativePath(a:path)
    let head = join(s:project_base, ',').'/'.head
    let tail = a:path
  else
    let tail = s:GetPathTail(a:path)
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
  let cmd = 'Project '.a:path
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
    if s:Include(line, target_pat)
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
      autocmd BufEnter * ++once call s:TryAutoloadOnBufEnter()
      autocmd VimEnter * ++once call s:AutoloadOnVimEnter()
    endif
    if s:auto_detect != 'no'
      autocmd BufEnter * call s:AutoDetectProject()
    endif
  augroup END
endfunction

function! s:TryAutoloadOnBufEnter()
  if !v:vim_did_enter
    let buf = expand('<amatch>')
    let project = s:GetProjectByPath(s:projects, buf)

    if !empty(project)
      let s:start_buf = buf
      let s:start_project = project
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
  let project = s:start_project
  if !empty(project)
    let buf = expand('<amatch>')
    " Avoid conflict with opened buffer like nerdtree
    enew
    execute 'ProjectOpen '.project.name

    if project.fullpath is s:start_buf
      " Follow session files if open the entry path
      " Use timer to avoid conflict with Fern.vim
      call timer_start(1, 'VimProject_HandleFileManagerPlugin')
    else
      " Otherwise edit the current file
      execute 'edit '.s:start_buf
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
      let ignore = s:GetProjectByFullpath(s:projects_ignore, path)

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

function! s:GetPathContain(buf, pats)
  let segments = split(a:buf, '/\|\\', 1)
  let depth = len(segments)

  for i in range(0, depth-1)
    let path = join(segments[0:depth-1-i], '/')
    for p in a:pats
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

function! s:GetProjectByPath(projects, path)
  let projects = copy(a:projects)
  call filter(projects, {_, project -> s:Include(a:path, project.fullpath)})
  if len(projects) == 1
    return projects[0]
  endif
  if len(projects) > 1
    call sort(projects, {i1, i2 -> len(i2.fullpath) - len(i1.fullpath)})
    return projects[0]
  endif

  return {}
endfunction

function! s:Warn(msg)
  redraw
  echohl WarningMsg
  echom '['.s:name.'] '.a:msg
  echohl None
endfunction

function! project#ListProjects()
  call s:PrepareListBuffer()
  let Init = function('s:ProjectListBufferInit')
  let Update = function('s:ProjectListBufferUpdate')
  let Open = function('s:ProjectListBufferOpen')
  let s:prefix = s:project_list_prefix
  let s:list_type = 'PROJECTS'
  call s:RenderList(Init, Update, Open)
endfunction

function! project#SearchFiles()
  if !s:ProjectExists()
    call s:Warn('No project opened')
    return
  endif

  call s:PrepareListBuffer()
  let Init = function('s:SearchFilesBufferInit')
  let Update = function('s:SearchFilesBufferUpdate')
  let Open = function('s:SearchFilesBufferOpen')
  let s:prefix = s:search_files_prefix
  let s:list_type = 'SEARCH_FILES'
  call s:RenderList(Init, Update, Open)
endfunction

function! project#FindInFiles()
  if !s:ProjectExists()
    call s:Warn('No project opened')
    return
  endif

  call s:PrepareListBuffer()
  let Init = function('s:FindInFilesBufferInit')
  let Update = function('s:FindInFilesBufferUpdateTimer')
  let Open = function('s:FindInFilesBufferOpen')
  let s:prefix = s:find_in_files_prefix
  let s:list_type = 'FIND_IN_FILES'
  call s:RenderList(Init, Update, Open)
endfunction

function! s:PrepareListBuffer()
  " Manually trigger some events first
  doautocmd BufLeave
  doautocmd FocusLost

  " Ignore events to avoid a cursor bug when opening from Fern.vim
  let save_eventignore = &eventignore
  set eventignore=all

  call s:OpenListBuffer()
  call s:SetupListBuffer()

  let &eventignore = save_eventignore
endfunction

function! s:OpenListBuffer()
  let s:max_height = winheight(0) - 5
  let s:max_width = &columns
  let win = s:list_buffer
  let num = bufwinnr(win)
  if num == -1
    execute 'silent botright split '.win
  else
    execute num.'wincmd w'
  endif
endfunction

function! s:CloseListBuffer(cmd)
  let &g:laststatus = s:laststatus_save

  if !s:IsCurrentListBuffer() || a:cmd == 'switch_to_list'
    return
  endif

  quit
  redraw
  wincmd p
endfunction

function! s:WipeoutListBuffer()
  let num = bufnr(s:list_buffer)
  if num != -1
    execute 'silent bwipeout! '.num
  endif
endfunction

function! s:SetupListBuffer()
  autocmd QuitPre <buffer> call s:WipeoutListBuffer()

  setlocal buftype=nofile bufhidden=delete nobuflisted
  setlocal filetype=projectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set laststatus=0

  syntax clear
  syntax match FirstColumn /^\S*/
  syntax match Comment /file results\|recently opened/
  syntax match Special / \.\.\.more$/

  highlight link ItemSelected CursorLine
  highlight link FirstColumn Keyword
  highlight link InfoColumn Comment
  highlight link InputChar Constant
  highlight link BeforeReplace Comment
  highlight link AfterReplace Function
  highlight! link SignColumn Noise

  sign define selected text=> texthl=ItemSelected linehl=ItemSelected
endfunction

function! s:IsCurrentListBuffer()
  return expand('%') == s:list_buffer
endfunction

function! s:HighlightCurrentLine(list_length)
  let length = a:list_length
  sign unplace 9
  if length > 0
    if s:offset > 0
      let s:offset = 0
    endif
    if s:offset < 1 - length
      let s:offset = 1 - length
    endif

    let current = length + s:offset

    if length < s:initial_height
      " Add extra empty liens to keep initial height
      let current += s:initial_height - length
    endif
    execute 'sign place 9 line='.current.' name=selected'
  endif

  if length > s:max_height
    normal! G
    execute 'normal! '.string(current).'G'
  endif
endfunction

function! s:ShowInListBuffer(display, input)
  " Avoid clearing other files by mistake
  if !s:IsCurrentListBuffer()
    return
  endif

  call s:AddToListBuffer(a:display)
  let length = len(a:display)
  call s:AdjustHeight(length, a:input)
  call s:AddEmptyLines(length)

  call s:RemoveExtraBlankLineAtBottom()
endfunction

function! s:RemoveExtraBlankLineAtBottom()
  normal! Gdd
  normal! gg
  normal! G
endfunction

function! s:AddToListBuffer(display)
  normal! ggdG
  if len(a:display) > 0
    call append(0, a:display)
  endif
endfunction

function! s:AdjustHeight(length, input)
  if (a:input == '' && s:initial_height == 0)
    if a:length == 0
      let s:initial_height = s:max_height
    else
      let s:initial_height = a:length
    endif
  endif
  if winheight(0) != s:initial_height
    execute 'resize '.s:initial_height
  endif
endfunction

function! s:AddEmptyLines(current)
  if a:current < s:initial_height
    let counts = s:initial_height - a:current
    call append(0, repeat([''], counts))
  endif
endfunction

function! s:FilterProjectsList(list, filter, origin_filter)
  let list = a:list
  let filter = a:filter
  let origin_filter = a:origin_filter

  for item in list
    let item._match_type = ''
    let item._match_index = -1

    " Filter by name
    let match_index = match(item.name, filter)
    if match_index != -1
      " Prefer continous match
      if len(origin_filter) > 1 && count(item.name, origin_filter) == 0
        let match_index = match_index + 10
      endif
      let item._match_type = 'name'
      let item._match_index = match_index
    endif

    " Filter by note
    if item._match_type != 'name'
      if has_key(item.option, 'note')
        let match_index = match(item.option.note, filter)
        if match_index != -1
          let item._match_type = 'note'
          let item._match_index = match_index
        endif
      endif
    endif

    " Filter by path
    if item._match_type == ''
      let match_index = match(item.path, filter)
      if match_index != -1
        let item._match_type = 'path'
        let item._match_index = match_index
      endif
    endif

    " Filter by path+name
    if item._match_type == ''
      let match_index = match(item.path.item.name, filter)
      if match_index != -1
        let item._match_type = 'path_name'
        let item._match_index = match_index
      endif
    endif
  endfor

  let result = filter(copy(list), { _, value -> value._match_type == 'name' || value._match_type == 'note' })
  if len(result) == 0
    let result = filter(list, { _, value -> value._match_type != '' })
  endif
  call sort(result, 's:SortProjectsList')
  return result
endfunction

function! s:SortProjectsList(a1, a2)
  let type1 = a:a1._match_type
  let type2 = a:a2._match_type
  let index1 = a:a1._match_index
  let index2 = a:a2._match_index

  " name > path_name > note > path
  if type1 == 'name' && type2 != 'name'
    return 1
  endif
  if type1 == 'path_name' && type2 != 'name' && type2 != 'path_name'
    return 1
  endif
  if type1 == 'note' && type2 == 'path'
    return 1
  endif
  if type1 == type2
    if index1 == index2
      return len(a:a2.name) - len(a:a1.name)
    else
      return index2 - index1
    endif
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
    let projects = s:FilterProjectsList(projects, filter, a:filter)
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

function! s:TabulateList(list, keys, max_col_width, no_limit_keys)
  let list = a:list
  let max_col_width = a:max_col_width

  " Get max width of each column
  let max = {}
  for item in list
    for key in a:keys
      if has_key(item, key)
        let value = s:ReplaceHomeWithTide(item[key])
        let item['__'.key] = value

        if !has_key(max, key) || len(value) > max[key]
          let max[key] = len(value)
        endif
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
        if has_key(item, key)
          let value = item['__'.key]
          if len(value) > max_col_width && count(a:no_limit_keys, key) == 0
            let value = value[0:max_col_width-2].'..'
            let item['__'.key] = value
          endif
          if !has_key(max, key) || len(value) > max[key]
            let max[key] = len(value)
          endif
        endif
      endfor
    endfor
  endif

  " Add right padding
  for item in list
    for key in a:keys
      if has_key(item, key)
        let item['__'.key] = s:AddRightPadding(item['__'.key], max[key])
      endif
    endfor
  endfor
endfunction

function! s:GetListCommand(char)
  let command = ''
  for [key, value] in items(s:list_map)
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

function! s:ProjectListBufferInit(input)
  let max_col_width = s:max_width / 2 - 10
  call s:TabulateList(s:projects, ['name', 'path', 'note'], max_col_width, ['note'])
  return s:ProjectListBufferUpdate(a:input)
endfunction

function! s:ProjectListBufferUpdate(input)
  let list = s:FilterProjects(copy(s:projects), a:input)
  let s:list = list

  let display = s:GetProjectsDisplay(list)
  call s:ShowInListBuffer(display, a:input)

  call s:HighlightCurrentLine(len(display))
  call s:HighlightInputChars(a:input)
endfunction

function! s:ProjectListBufferOpen(project, open_cmd)
  if empty(a:project)
    call s:Warn('No project selected')
    return
  endif

  if s:IsValidProject(a:project)
    call s:OpenProject(a:project)
  else
    call s:Warn('Not accessible path: '.a:project.fullpath)
  endif
endfunction

function! s:SortFilesList(input, a1, a2)
  let file1 = a:a1.file
  let file2 = a:a2.file
  let first = '\c'.a:input[0]

  let start1 = match(file1, first)
  let start2 = match(file2, first)
  if start1 == start2
    return len(file1) - len(file2)
  elseif start1 != -1 && start2 != -1
    return start1 - start2
  else
    return start1 == -1 ? 1 : -1
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
  if s:IsListMore(a:list)
    let display[0] .= '  ...more'
  endif
  return display
endfunction

function! s:GetSearchFilesDisplayRow(idx, value)
  let value = a:value
  let full_path = $vim_project.'/'.value.path.'/'.value.file
  if isdirectory(full_path)
    let file = substitute(value.__file, '\S\zs\s\|\S\zs$', '/', '')
  else
    let file = value.__file
  endif
  return file.'  '.value.__path
endfunction

function! s:GetSearchFilesByOldFiles(input)
  let oldfiles = s:GetOldFiles()

  call s:FilterOldFilesByPath(oldfiles)

  call s:MapSearchFiles(oldfiles)

  call s:FilterOldFilesByInput(oldfiles, a:input)

  call s:SortSearchFiles(oldfiles, a:input)

  return oldfiles
endfunction

function! s:GetOldFiles()
  let oldfiles = copy(v:oldfiles)

  for buf in getbufinfo({'buflisted': 1})
    if count(oldfiles, s:ReplaceHomeWithTide(buf.name)) == 0
      call insert(oldfiles, buf.name)
    endif
  endfor
  return oldfiles
endfunction

function! s:FilterOldFilesByPath(oldfiles)
  call map(a:oldfiles, {_, val -> fnamemodify(val, ':p')})

  let project_dir = fnamemodify($vim_project, ':p')
  call filter(a:oldfiles, {_, val ->
        \ count(val, project_dir) > 0
        \ && count(['ControlP', ''], fnamemodify(val, ':t')) == 0
        \ && (filereadable(val) || isdirectory(val))
        \})

  let search_exclude = copy(s:search_exclude)
  call map(search_exclude, {_, val -> fnamemodify($vim_project.'/'.val, ':p')})
  call filter(a:oldfiles, {_, val -> !s:IsPathStartWithAny(val, search_exclude)})

  call map(a:oldfiles, {_, val -> substitute(val, project_dir, './', '')})
endfunction

function! s:IsPathStartWithAny(fullpath, starts)
  for start in a:starts
    if match(a:fullpath, start) == 0
      return 1
    endif
  endfor

  return 0
endfunction

function! s:FilterOldFilesByInput(oldfiles, input)
  let pattern = join(split(a:input, '\zs'), '.*')
  call filter(a:oldfiles,
        \{_, val -> val.file =~ pattern})
endfunction

function! s:GetFilesByFind()
  let include = join(s:search_include, ' ')

  let search_exclude = copy(s:search_exclude)
  let exclude_string = join(map(search_exclude, {_, val -> '-name '.val}), ' -o ')
  let exclude = '\( '.exclude_string.' \) -prune -false -o '

  let filter = '-ipath "*"'
  let cmd = 'find '.include.' -mindepth 1 '.exclude.filter
  let result = s:RunShellCmd(cmd)
  return result
endfunction

function! s:GetFilesByFd()
  let include = join(s:search_include, ' ')

  let search_exclude = copy(s:search_exclude)
  let exclude = join(map(search_exclude, {_, val -> '-E '.val}), ' ')

  let cmd = 'fd -HI '.exclude.' . '.include
  let result = s:RunShellCmd(cmd)
  return result
endfunction

function! s:GetFilesByGlob()
  let original_wildignore = &wildignore
  let cwd = getcwd()
  execute 'cd '.$vim_project
  for exclue in s:search_exclude
    execute 'set wildignore+=*/'.exclue.'*'
  endfor

  let result = []
  for path in s:search_include
    let result = result + glob(path.'/**/*', 0, 1)
  endfor

  execute 'cd '.cwd
  let &wildignore = original_wildignore
  return result
endfunction

function! s:GetSearchFilesResultList(input)
  if !exists('s:list_initial_result')
    let list = s:GetSearchFilesAll()
  else
    let list = s:GetSearchFilesByFilter(a:input)
  endif
  return list
endfunction

function! s:TrySearchFilesProgram()
  let programs = ['fd', 'find']
  let find_cmd_map = {
        \'fd': function('s:GetFilesByFd'),
        \'find': function('s:GetFilesByFind'),
        \'glob': function('s:GetFilesByGlob'),
        \}
  let find_program = ''
  for program in programs
    if executable(program)
      let find_program = program
      break
    endif
  endfor

  if find_program == ''
    let find_program = 'glob'
  endif

  let s:find_cmd_func = find_cmd_map[find_program]
  return find_program
endfunction

function! s:GetSearchFilesAll()
  if !exists('s:find_cmd_func')
    call s:TrySearchFilesProgram()
  endif

  let result = s:find_cmd_func()
  call s:MapSearchFiles(result)
  let s:list_initial_result = result
  let list = copy(s:list_initial_result)
  return list
endfunction

function! s:GetSearchFilesByFilter(input)
  " file
  let filter0 = a:input
  let list = []

  if len(a:input) < 3
    let filter1 = '^'.filter0
    let list = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter1})
  endif

  if len(list) < s:max_height
    let list = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter0})
    " Avoid sort long list for performance
    call s:SortSearchFiles(list, a:input)
  endif

  if len(list) < s:max_height
    let filter2 = join(split(a:input, '\zs'), '.*')
    let list2 = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter2})
    call s:SortSearchFiles(list2, a:input)
    let list += list2
  endif

  " path.file
  if len(list) < s:max_height
    let list2 = filter(copy(s:list_initial_result), {_, val -> val.path.val.file =~ filter0})
    let list += list2
  endif

  if len(list) < s:max_height
    let list2 = filter(copy(s:list_initial_result), {_, val -> val.path.val.file =~ filter2})
    let list += list2
  endif
  return list
endfunction

function! s:GetSearchFiles(input)
  let oldfiles = s:GetSearchFilesByOldFiles(a:input)
  let search_list = s:GetSearchFilesResultList(a:input)

  let list = oldfiles + search_list

  let max_length = s:max_height - 1
  let list = list[0:max_length*3]
  call s:UniqueList(list)
  if len(list) > max_length
    let list = list[0:max_length]
    let list[-1].more = 1
  endif

  call reverse(list)
  return [list, oldfiles]
endfunction

function! s:MapSearchFiles(list)
  call map(a:list, {idx, val ->
        \{
        \'file': fnamemodify(val, ':t'),
        \'path': fnamemodify(val, ':h:s+\./\|^\.$++'),
        \}})
endfunction

function! s:SortSearchFiles(list, input)
  if !empty(a:input) && len(a:list) > 0
    call sort(a:list, function('s:SortFilesList', [a:input]))
  endif
endfunction

function! s:GetSearchFilesResult(input)
  let [list, oldfiles] = s:GetSearchFiles(a:input)
  let max_col_width = s:max_width / 8 * 5
  call s:TabulateList(list, ['file', 'path'], max_col_width, ['path'])
  let display = s:GetSearchFilesDisplay(list, len(oldfiles))
  return [list, display]
endfunction

function! s:SearchFilesBufferInit(input)
  return s:SearchFilesBufferUpdate(a:input)
endfunction

function! s:SearchFilesBufferUpdate(input)
  if a:input != s:input
    let [list, display] = s:GetSearchFilesResult(a:input)
    call s:ShowInListBuffer(display, a:input)
    let s:input = a:input
    let s:list = list
  endif

  call s:HighlightCurrentLine(len(s:list))
  call s:HighlightInputChars(a:input)
endfunction

function! s:SearchFilesBufferOpen(target, open_cmd)
  let cmd = substitute(a:open_cmd, 'open_\?', '', '')
  let cmd = cmd == '' ? 'edit' : cmd
  let file = $vim_project.'/'.a:target.path.'/'.a:target.file
  execute cmd.' '.file
endfunction

function! s:TryExternalGrepProgram()
  " Try rg, ag, grep, vimgrep in order
  let programs = ['rg', 'ag', 'grep']
  let grep_cmd_map = {
        \'rg': function('s:GetRgCmd'),
        \'ag': function('s:GetAgCmd'),
        \'grep': function('s:GetGrepCmd'),
        \}

  let grep_program = ''
  for program in programs
    if executable(program)
      let grep_program = program
      break
    endif
  endfor

  if grep_program != ''
    let s:grep_cmd_func = grep_cmd_map[grep_program]
    return grep_program
  else
    let s:grep_cmd_func = 0
    return 'vimgrep'
  endif
endfunction


function! s:GetGrepResult(search, full_input)
  if !exists('s:grep_cmd_func')
    call s:TryExternalGrepProgram()
  endif

  let flags = s:GetSearchFlags(a:search)
  let search = s:RemoveSearchFlags(a:search)

  if s:grep_cmd_func != 0
    let list = s:RunExternalGrep(search, flags, a:full_input)
  else
    let list = s:RunVimGrep(search, flags, a:full_input)
  endif

  let result = s:GetJoinedList(list)
  return result
endfunction

function! s:GetAgCmd(pattern, flags)
  let include = copy(s:find_in_files_include)
  let include_arg = join(include, ' ')

  let exclude = copy(s:find_in_files_exclude)
  let exclude_arg = join(
        \map(exclude,{_, val -> '--ignore-dir '.val}), ' ')

  let search_arg = '--hidden --skip-vcs-ignores'
  if s:Include(a:flags, 'C')
    let search_arg .= ' --case-sensitive'
  else
    let search_arg .= ' --ignore-case'
  endif
  if !s:Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'ag '.search_arg.' '.include_arg.' '.exclude_arg.' '.a:pattern
  return cmd
endfunction

function! s:GetGrepCmd(pattern, flags)
  let include = copy(s:find_in_files_include)
  let include_arg = join(include, ' ')
  if empty(include_arg)
    let include_arg = '.'
  endif

  let exclude = copy(s:find_in_files_exclude)
  let exclude_arg = join(
        \map(exclude,{_, val -> '--exclude-dir '.val}), ' ')

  let search_arg = '--line-number --recursive'
  if !s:Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if !s:Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'fgrep '.search_arg.' '.a:pattern.' '.include_arg.' '.exclude_arg
  return cmd
endfunction

function! s:GetRgCmd(pattern, flags)
  let include = copy(s:find_in_files_include)
  " Remove '.', as rg does not support '{./**}'
  call filter(include, {_, val -> val != '.'})

  if len(include)
    let include_pattern = map(include, 
          \{_, val -> val.'/**' })
    let include_arg = "-g '{".join(include_pattern, ',')."}'"
  else
    let include_arg = "-g '{**}'"
  endif

  let exclude = copy(s:find_in_files_exclude)
  let exclude_arg = "-g '!{".join(exclude, ',')."}'"

  let search_arg = '--line-number --no-ignore-vcs'
  if !s:Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if !s:Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'rg '.search_arg.' '.include_arg.' '.exclude_arg.' '.a:pattern
  return cmd
endfunction

function! s:RunExternalGrep(search, flags, full_input)
  let pattern = '"'.escape(a:search, '"').'"'
  let cmd = s:grep_cmd_func(pattern, a:flags)

  let output = s:RunShellCmd(cmd)
  let result = s:GetResultFromGrepOutput(a:search, a:full_input, output)
  return result
endfunction


function! s:SetGrepOutputLength(input, full_input, output)
  let output = a:output
  let more = 0

  let replace_initially_added = s:IsReplaceInitiallyAdded(a:full_input)
  let exceed_max_to_stop = len(output) > s:find_in_files_to_stop_max

  if !replace_initially_added
    let max_length = s:find_in_files_max
    if len(output) > max_length
      let output = output[0:max_length]
      let more = 1
    endif
  elseif exceed_max_to_stop
    let error_msg = 'Error: :Stopped for too many matches, more than '
          \.s:find_in_files_to_stop_max
    let output = [error_msg]
  endif

  return [output, more]
endfunction

function! s:GetResultFromGrepOutput(input, full_input, output)
  let [output, more] = s:SetGrepOutputLength(a:input, a:full_input, a:output)

  let result = map(map(output, {_, val -> split(val, ':')}), {_, val -> {
        \'file': val[0],
        \'lnum': val[1],
        \'line': join(val[2:], ':'),
        \}})

  if more
    let result[0].more = more
  endif
  return result
endfunction

function! s:HasFile(list, file)
  for item in a:list
    if has_key(item, 'file') && item.file == a:file
      return 1
    endif
  endfor
  return 0
endfunction

function! s:GetJoinedList(list)
  let joined_list = []
  let current_file = ''

  " Assume the list has already been ordered by file
  for item in a:list
    if item.file != current_file
      let current_file = item.file
      call add(joined_list, { 'file': item.file })
    endif
    call add(joined_list, item)
  endfor

  if len(a:list) && has_key(a:list[0], 'more')
    let joined_list[0].more = a:list[0].more
  endif
  return joined_list
endfunction

function! s:RunVimGrep(search, flags, full_input)
  let original_wildignore = &wildignore
  for exclude in s:find_in_files_exclude
    execute 'set wildignore+=*/'.exclude.'*'
  endfor

  let pattern_flag = ''
  if s:Include(a:flags, 'C')
    let pattern_flag .= '\C'
  else
    let pattern_flag .= '\c'
  endif
  if s:Include(a:flags, 'E')
    let pattern_flag .= '\v'
  else
    let pattern_flag .= '\V'
  endif

  let pattern = '/'.pattern_flag.escape(a:search, '/').'/j'
  let cmd = 'silent! vimgrep '.pattern.' '.$vim_project.'/**/*'
  execute cmd
  redraw!

  let &wildignore = original_wildignore

  let output_qf = getqflist()

  let [output, more] = s:SetGrepOutputLength(a:search, a:full_input, output_qf)

  let result = map(output, {_, val -> {
        \'file': s:RemoveProjectPath(getbufinfo(val.bufnr)[0].name),
        \'lnum': val.lnum,
        \'line': val.text,
        \}})

  if more
    let result[0].more = more
  endif
  return result
endfunction

function! s:RunShellCmd(cmd)
  let cmd = 'cd '.$vim_project.' && '.a:cmd
  try
    let output = systemlist(cmd)
  catch
    return []
  endtry

  if v:shell_error
    if !empty(output)
      call s:Debug(a:cmd.': '.string(output))
    endif
    return []
  endif

  return output
endfunction

function! s:GetFindInFilesResult(search, full_input)
  let raw_search = s:RemoveSearchFlags(a:search)
  if raw_search == '' || len(raw_search) == 1
    return []
  endif

  let list = s:GetGrepResult(a:search, a:full_input)
  return list
endfunction

function! s:GetFindInFilesDisplay(list, search, replace)
  if len(a:list) == 0
    return []
  endif

  let pattern = s:GetFindInFilesSearchPattern(a:search)
  let show_replace = !empty(a:search) && !empty(a:replace)

  let display = map(copy(a:list),
        \function('s:GetFindInFilesDisplayRow', [pattern, a:replace, show_replace]))

  if s:IsListMore(a:list)
    let display[0] .= '  ...more'
  endif

  return display
endfunction

function! s:IsFileItem(item)
  return has_key(a:item, 'file') && !has_key(a:item, 'line')
endfunction

function! s:IsFileLineItem(item)
  return has_key(a:item, 'file') && has_key(a:item, 'line')
endfunction

function! s:GetFindInFilesDisplayRow(pattern, replace, show_replace, idx, val)
  let isFile = s:IsFileItem(a:val)
  if isFile
    return a:val.file
  else
    let line = a:val.line
    if a:show_replace
      let line = s:GetReplacedLine(line, a:pattern, a:replace, 1)
    endif
    return '  '.line
  endif
endfunction

function! s:GetReplacedLine(line, pattern, replace, add)
  let prefix = a:add ? '\1' : ''
  let line = substitute(a:line, '\V\('.a:pattern.'\V\)', prefix.a:replace, 'g')
  return line
endfunction

function! s:IsListMore(list)
  return len(a:list) && has_key(a:list[0], 'more') && a:list[0].more
endfunction

function! s:FindInFilesBufferInit(input)
  return s:FindInFilesBufferUpdate(a:input, 1, 0)
endfunction


function! s:FindInFilesBufferUpdateTimer(input)
  call timer_stop(s:update_timer)
  if !s:ShouldRunFindInFiles(a:input)
    call s:FindInFilesBufferUpdate(a:input, 0, 0)
  else
    let s:update_timer = timer_start(350,
          \function('s:FindInFilesBufferUpdate', [a:input, 0]))
  endif
endfunction

function! s:IsReplaceInitiallyAdded(input)
  let [_, replace] = s:ParseInput(a:input)
  let has_separator = s:Include(a:input, s:search_replace_separator)
  return has_separator && empty(replace) && s:replace == -1
endfunction

function! s:ShouldRunFindInFiles(input)
  let [search, replace] = s:ParseInput(a:input)
  let search_changed = exists('s:input') && search != s:input && !s:IsShowHistoryList(search)
  let replace_initially_added = s:IsReplaceInitiallyAdded(a:input)
  return search_changed || replace_initially_added
endfunction

function! s:IsShowHistoryList(input)
  return a:input == '' && s:input == -1 && !empty(s:list)
endfunction

function! s:GetSearchFlags(search)
  let case_sensitive = s:Include(a:search, '\\C')
  let use_regexp = s:Include(a:search, '\\E')

  let flags = ''
  if case_sensitive
    let flags .= 'C'
  endif
  if use_regexp
    let flags .= 'E'
  endif
  return flags
endfunction

function! s:RemoveSearchFlags(search)
  return substitute(a:search, '\\C\|\\E', '', 'g')
endfunction

function! s:ParseInput(input)
  let inputs = split(a:input, s:search_replace_separator)

  if len(inputs) == 2
    let search = inputs[0]
    let replace = inputs[1]
  elseif len(inputs) == 1
    let search = inputs[0]
    let replace = ''
  else
    let search = a:input
    let replace = ''
  endif

  return [search, replace]
endfunction

function! s:ShowFindInFilesResultTimer(display, search, replace, full_input)
  call timer_start(1,
        \function('s:ShowFindInFilesResult', [a:display, a:search, a:replace, a:full_input]))
endfunction
" 
function! s:ShowFindInFilesResult(display, search, replace, full_input, id)
  if exists('s:list')
    call s:ShowInListBuffer(a:display, a:search)
    call s:HighlightCurrentLine(len(s:list))
    call s:HighlightSearchAsPattern(a:search)
    call s:HighlightReplaceChars(a:search, a:replace)
    call s:ShowInputLine(a:full_input)
  endif
endfunction

function! s:FindInFilesBufferUpdate(full_input, is_init, id)
  let [search, replace] = s:ParseInput(a:full_input)
  let should_run = s:ShouldRunFindInFiles(a:full_input)
  let should_redraw = s:ShouldRedrawWithReplace(search, replace)

  if should_run
    let list = s:GetFindInFilesResult(search, a:full_input)
    let display = s:GetFindInFilesDisplay(list, search, replace)
    let s:input = search
    let s:list = list
    if s:IsReplaceInitiallyAdded(a:full_input)
      let s:replace = replace
    else
      let s:replace = -1
    endif
  elseif should_redraw
    let [redraw_search, redraw_replace] =
          \s:TryGetSearchAndReplaceFromHistory(search, replace)
    let display = s:GetFindInFilesDisplay(s:list, redraw_search, redraw_replace)
    let s:replace = replace
  else
    let display = s:GetFindInFilesDisplay(s:list, search, replace)
  endif

  " Use timer just for fluent typing. Not necessary
  let use_timer = (should_run || should_redraw) && !empty(a:full_input) && !a:is_init
  if use_timer
    call s:ShowFindInFilesResultTimer(display, search, replace, a:full_input)
  else
    call s:ShowFindInFilesResult(display, search, replace, a:full_input, 0)
  endif
endfunction

function! s:TryGetSearchAndReplaceFromHistory(search, replace)
  if s:IsShowHistoryList(a:search) && s:HasFindInFilesHistory()
    let input = s:list_history.FIND_IN_FILES.input
    return s:ParseInput(input)
  else
    return [a:search, a:replace]
  endif
endfunction

function! s:HasFindInFilesHistory()
  return has_key(s:list_history, 'FIND_IN_FILES')
endfunction

function! s:IsDismissed()
  return s:dismissed_find_replace
endfunction

function! s:ResetDismissedVar()
  if s:dismissed_find_replace
    let s:dismissed_find_replace = 0
  endif
endfunction

function! s:ShouldRedrawWithReplace(input, replace)
  if s:IsDismissed()
    return 1
  endif
  if empty(a:replace) && s:replace == -1
    return 0
  endif
  return a:replace != s:replace && !s:IsShowHistoryList(a:input)
endfunction

function! s:HighlightReplaceChars(search, replace)
  if a:replace == ''
    return
  endif

  let pattern = s:GetFindInFilesSearchPattern(a:search)
  execute 'silent! 3match BeforeReplace /'.pattern.'/'
  execute 'silent! 2match AfterReplace /'.pattern.'\zs\V'.a:replace.'/'
  execute 'silent! 1match FirstColumn /^\S*/'
endfunction

function! s:FindInFilesBufferOpen(target, open_cmd)
  let open_type = substitute(a:open_cmd, 'open_\?', '', '')
  if open_type == ''
    let open_type = 'edit'
  endif

  let file = $vim_project.'/'.a:target.file
  let lnum = has_key(a:target, 'lnum') ? a:target.lnum : 1
  execute open_type.' +'.lnum.' '.file
endfunction

function! s:ShowInputLine(input)
  if len(s:list) > s:find_in_files_max * 2
    let total = '('.len(s:list).')'
  else
    let total = ''
  endif

  redraw
  echo s:prefix.total.' '.a:input
endfunction

function! s:ShowInitialInputLineTimer(input)
  call timer_start(100, function('s:ShowInitialInputLine', [a:input]))
endfunction

function! s:ShowInitialInputLine(input, ...)
  call s:ShowInputLine(a:input)
endfunction

function! s:RenderList(Init, Update, Open)
  let input = s:InitListVariables(a:Init)
  call s:ShowInitialInputLine(input)
  " call s:ShowInitialInputLineTimer(input)

  let [cmd, input] = s:HandleInput(input, a:Update)

  call s:CloseListBuffer(cmd)
  if s:IsOpenCmd(cmd)
    call s:OpenTarget(cmd, a:Open)
  endif
  call s:SaveListVariables(input)
  call s:ResetListVariables()
endfunction

function! s:InitListVariables(Init)
  let has_history = has_key(s:list_history, s:list_type)
  if has_history
    let prev = s:list_history[s:list_type]
    let input = prev.input
    let s:offset = prev.offset
    let s:initial_height = prev.initial_height
  else
    let input = ''
    let s:offset = 0
  endif

  " Make sure s:input (saved input), s:replace (saved replace)
  " is differrent from input to trigger query
  let s:input = -1
  let s:replace = -1
  let s:list = []

  call a:Init(input)

  " Empty input if it was set from history
  if has_history
    let s:input = -1
    let input = ''
  endif

  return input
endfunction

function! s:GetUserInputChar()
  let c = getchar()
  let char = type(c) == v:t_string ? c : nr2char(c)
  return char
endfunction

function! s:ClearCharOfInput(input)
  let length = len(a:input)
  let input = length == 1 ? '' : a:input[0:length-2]
  return input
endfunction

function! s:ClearWordOfInput(input)
  if a:input =~ '\w\s*$'
    let input = substitute(a:input, '\w*\s*$', '', '')
  else
    let input = substitute(a:input, '\W*\s*$', '', '')
  endif
  return input
endfunction

function! s:AddFindReplaceSeparator(input)
  if !s:Include(a:input, s:search_replace_separator)
    let input = a:input.s:search_replace_separator
  else
    let input = a:input
  endif

  return input
endfunction

function! s:HandleInput(input, Update)
  let input = a:input

  try
    while 1
      let char = s:GetUserInputChar()
      let cmd = s:GetListCommand(char)
      if cmd == 'close_list'
        break
      elseif cmd == 'clear_char'
        let input = s:ClearCharOfInput(input)
      elseif cmd == 'clear_word'
        let input = s:ClearWordOfInput(input)
      elseif cmd == 'clear_all'
        let input = ''
      elseif cmd == 'prev_item'
        let s:offset -= 1
      elseif cmd == 'next_item'
        let s:offset += 1
      elseif cmd == 'first_item'
        let s:offset = 1 - len(s:list)
      elseif cmd == 'last_item'
        let s:offset = 0
      elseif cmd == 'next_view'
        call s:NextView()
      elseif cmd == 'prev_view'
        call s:PreviousView()
      elseif cmd == 'scroll_up'
        let s:offset = s:offset - winheight(0)/2
      elseif cmd == 'scroll_down'
        let s:offset = s:offset + winheight(0)/2
      elseif cmd == 'replace_prompt'
        let input = s:AddFindReplaceSeparator(input)
      elseif cmd == 'replace_dismiss'
        call s:DismissFindReplaceItem()
      elseif cmd == 'replace_confirm'
        call s:ConfirmFindReplace(input)
        break
      elseif cmd == 'switch_to_list'
        break
      elseif s:IsOpenCmd(cmd)
        break
      else
        let input = input.char
      endif

      call a:Update(input)
      call s:ShowInputLine(input)
    endwhile
  catch /^Vim:Interrupt$/
    call s:Debug('Interrupt')
  finally
  endtry

  return [cmd, input]
endfunction

function! s:ConfirmFindReplace(input)
  let [current_search, current_replace] = s:ParseInput(a:input)
  let [search, replace] =
        \s:TryGetSearchAndReplaceFromHistory(current_search, current_replace)
  call s:RunReplaceAll(search, replace)
endfunction

function! s:RunReplaceAll(search, replace)
  let index_line = 0
  let index_file = 0
  let total_lines = s:GetTotalReplaceLines()
  let total_files = len(s:list) - total_lines
  let pattern = s:GetFindInFilesSearchPattern(a:search)

  for item in s:list
    if s:IsFileLineItem(item)
      call s:ReplaceLineOfFile(item, pattern, a:replace)
      let index_line += 1
    else
      let index_file += 1
    endif
    let info_line = 'line '.index_line.' of '.total_lines
    let info_file = 'file '.index_file.' of '.total_files
    redraw
    call s:EchoInfo('Replaced '.info_file.', '.info_line)
  endfor
endfunction

function! s:GetTotalReplaceLines()
  let total = 0
  for item in s:list
    if s:IsFileLineItem(item)
      let total += 1
    endif
  endfor
  return total
endfunction

function! s:ReplaceLineOfFile(item, pattern, replace)
  let file = $vim_project.'/'.a:item.file
  let index = a:item.lnum - 1
  let lines = readfile(file)
  let lines[index] = s:GetReplacedLine(lines[index], a:pattern, a:replace, 0)
  call writefile(lines, file)
endfunction

function! s:DismissFindReplaceItem()
  let target = s:GetTarget()
  if empty(target)
    return
  endif

  if s:IsFileLineItem(target)
    call s:RemoveTarget()
  else
    call s:RemoveFile()
  endif
  let s:dismissed_find_replace = 1
endfunction

function! s:IsOpenCmd(cmd)
  let open_cmds = ['open', 'open_split', 'open_vsplit', 'open_tabedit']
  return count(open_cmds, a:cmd) > 0
endfunction

function! s:SaveListVariables(input)
  if s:list_type != 'FIND_IN_FILES'
    return
  endif

  let input = a:input

  if s:HasFindInFilesHistory() 
    let last_input = s:list_history[s:list_type].input
    if !empty(last_input) && s:IsShowHistoryList(a:input)
      let input = last_input
    endif
  endif

  let s:list_history[s:list_type] = {
        \'input': input,
        \'offset': s:offset,
        \'initial_height': s:initial_height,
        \}
endfunction

function! s:ResetListVariables()
  unlet! s:input
  let s:initial_height = 0

  unlet! s:list
  unlet! s:list_initial_result
  unlet! s:prefix
  unlet! s:list_type
endfunction

function! s:GetTarget()
  let index = len(s:list) - 1 + s:offset
  if index >= 0
    let target = s:list[index]
    return target
  endif

  return {}
endfunction

function! s:GetCurrentIndex()
  return len(s:list) - 1 + s:offset
endfunction

function! s:GetCurrentOffset(index)
  return a:index - len(s:list) + 1
endfunction

function! s:GetNextFileIndex(index)
  for i in range(a:index+1, len(s:list)-1)
    if s:IsFileItem(s:list[i])
      return i
    endif
  endfor

  return len(s:list)
endfunction

function! s:RemoveTarget()
  let index = s:GetCurrentIndex()
  call remove(s:list, index)
  call s:RemoveFileWithoutItem()
  call s:UpdateOffsetAfterRemoveTarget()
endfunction

function! s:UpdateOffsetAfterRemoveTarget()
  if s:offset < len(s:list) - 2
    let s:offset += 1
  endif
endfunction

function! s:RemoveFileWithoutItem()
  let target = s:GetTarget()
  if s:IsFileItem(target)
    let current_index = s:GetCurrentIndex()
    let next_file_index = s:GetNextFileIndex(current_index)
    if next_file_index - current_index < 2
      call s:RemoveTarget()
    endif
  endif
endfunction

function! s:RemoveFile()
  let index = s:GetCurrentIndex()
  let next_file_index = s:GetNextFileIndex(index)
  call s:RemoveRange(index, next_file_index - 1)
  call s:UpdateOffsetAfterRemoveFile(index)
endfunction

function! s:UpdateOffsetAfterRemoveFile(index)
  if a:index < len(s:list) - 2
    let s:offset = s:GetCurrentOffset(a:index)
  else
    let s:offset = 0
  endif
endfunction

function! s:RemoveRange(start, end)
  if a:start < a:end
    call remove(s:list, a:start, a:end)
  endif
endfunction

function! s:OpenTarget(cmd, Open)
  let target = s:GetTarget()
  call a:Open(target, a:cmd)
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

function! s:RemoveProjectByName(name, is_recursive)
  let project = s:GetProjectByName(a:name, s:projects)
  if empty(project)
    let project = s:GetProjectByName(a:name, s:projects_error)
  endif

  if !empty(project)
    call s:RemoveProject(project)
    call s:RemoveProjectByName(a:name, 1)
  elseif !a:is_recursive
    call s:Warn('Project not found: '.a:name)
  endif
endfunction

function! project#RemoveProjectByName(name)
  call s:RemoveProjectByName(a:name, 0)
endfunction

function! project#ReloadProject()
  call s:ReloadProject()
endfunction

function! s:ReloadProject()
  if s:ProjectExists()
    call s:SaveAllBuffers()
    let s:reloading_project = 1

    let project = s:project
    call s:QuitProject()
    call s:OpenProject(project)

    let s:reloading_project = 0
  endif
endfunction

function! s:SaveAllBuffers()
  wa
endfunction

function! s:OpenProject(project)
  let current = s:project
  let new = a:project

  if current != new
    call s:ClearCurrentProject(current)
    let s:project = new

    call s:PreLoadProject()
    call s:LoadProject()
    call s:PostLoadProject()

    redraw
    call s:Info('Open: '.new.name)
  else
    call s:Info('Already opened')
  endif
endfunction

function! s:PreLoadProject()
  call s:InitStartBuffer()
  call s:SetEnvVariables()
endfunction

function! s:LoadProject()
  call s:SourceInitFile()
  call s:FindBranch()
  call s:LoadSession()
endfunction

function! s:PostLoadProject()
  call s:SetStartBuffer()
  call s:SyncGlobalVariables()
  call s:StartWatchJob()
  call s:OnVimLeave()
endfunction

function! s:ClearCurrentProject(current)
  if s:ProjectExists()
    call s:QuitProject()
    silent! %bdelete
  endif
endfunction

function! s:RemoveProject(project)
  let target = a:project
  let projects = s:projects

  if target == s:project
    call s:QuitProject()
  endif

  let idx = index(projects, target)
  call remove(projects, idx)
  call s:Info('Removed: '. target.name.' at '.target.path)
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

function! s:ProjectExists()
  if empty(s:project)
    return 0
  else
    return 1
  endif
endfunction

function! project#OpenProjectEntry()
  if s:ProjectExists()
    let path = s:GetProjectEntryPath()
    if !empty(path)
      execute 'edit '.path
    endif
  endif
endfunction

function! project#OpenProjectConfig()
  if s:ProjectExists()
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    execute 'edit '.config
  endif
endfunction

function! project#OpenAllConfig()
  execute 'edit '.s:config_home
endfunction

function! project#QuitProject()
  call s:QuitProject()
endfunction

function! s:QuitProject()
  if s:ProjectExists()
    call s:Info('Quit: '.s:project.name)
    call s:SaveSession()
    call s:SourceQuitFile()

    let s:list_history = {}
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
    call s:Info('Name: '.s:project.name)
    call s:Info('Path: '.s:ReplaceHomeWithTide(s:project.path))
    call s:Info('Search: '.s:TrySearchFilesProgram())
    call s:Info('Find in files: '.s:TryExternalGrepProgram())
    call s:Info('----- Config -----')
    call s:ShowProjectConfig()
  else
    call s:Info('No project opened')
  endif
endfunction

function! s:ShowProjectConfig()
  for key in sort(keys(s:config))
    if has_key(s:, key)
      let value = s:[key]
    else
      let value = s:config[key]
    endif
    call s:Info(key.': '.string(value))
  endfor
endfunction

function! s:InitStartBuffer()
  if !s:reloading_project
    enew
  endif
endfunction

function! s:SetStartBuffer()
  if s:reloading_project
    return 0
  endif

  let path = s:GetProjectEntryPath()
  if s:ShouldOpenEntry()
    call s:OpenEntry(path)
  else
    execute 'cd '.path
  endif
endfunction

function! s:OpenEntry(path)
  let bufname = expand('%')
  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1
  if is_nerdtree_tmp
    silent bdelete
  endif

  call s:Debug('Open entry from buffer '.bufname)

  let path = a:path
  if empty(path)
    execute 'silent only | enew'
  else
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
  endif
endfunction

function! s:ShouldOpenEntry()
  let bufname = expand('%')
  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1

  return s:open_entry_when_use_session
        \|| &buftype == 'nofile'
        \|| bufname == ''
        \|| is_nerdtree_tmp
endfunction

function! s:GetProjectEntryPath()
  let path = s:project.fullpath
  " Remove the relative part './'
  let entry = substitute(s:project_entry, '^\.\?[/\\]', '', '')
  let path = path.'/'.entry
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
  call s:ResetConfig()
  call s:InitConfig()
  call s:SourceFile(s:init_file)
  call s:ReadLocalConfig()
  call s:AdjustConfig()
endfunction

function! s:ResetConfig()
  let g:vim_project_local_config = {}
endfunction

function! s:ReadLocalConfig()
  let local_config = s:GetConfig('local_config', {})
  if !empty(local_config)
    for key in s:local_config_keys
      if has_key(local_config, key)
        let s:[key] = local_config[key]
      endif
    endfor
  endif

  if has_key(local_config, 'file_map')
    call s:MapFile(local_config.file_map)
  endif
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
  if !s:check_branch_when_use_session
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
  if s:ProjectExists()
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    return config.'/sessions'
  else
    return ''
  endif
endfunction


function! s:GetSessionFile()
  if s:ProjectExists()
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    return config.'/sessions/'.s:branch.'.vim'
  else
    return ''
  endif
endfunction

function! s:LoadSession()
  if !s:use_session
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
  let should_watch = s:check_branch_when_use_session && executable('tail') == 1
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
  if !s:use_session
    return
  endif

  if s:ProjectExists()
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

function! s:MapFile(config)
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
    let s:GotoLinkFuncRef = function('s:GotoLinkedFile', [a:link])
  " It seems that only function... can be called by <SID> in map
    function! s:GotoLinkedFunc(open_type)
      call s:GotoLinkFuncRef(a:open_type)
    endfunction

    for [open_key, open_type] in items(s:open_types)
      execute "nnoremap '".open_key.a:link.key
            \.' :update<cr>:call <SID>GotoLinkedFunc("'.open_type.'")<cr>'
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

function! s:Include(string, search_string)
  return match(a:string, a:search_string) != -1
endfunction

function! s:GetFindInFilesSearchPattern(search)
  let flags = s:GetSearchFlags(a:search)
  let pattern_flags = ''
  if s:Include(flags, 'C')
    let pattern_flags .= '\C'
  else
    let pattern_flags .= '\c'
  endif
  if s:Include(flags, 'E')
    let pattern_flags .= '\v'
  else
    let pattern_flags .= '\V'
  endif

  let search = s:RemoveSearchFlags(a:search)
  let pattern = search
  let pattern = escape(pattern, '/')
  let pattern = s:TransformPatternOneByOne(pattern)
  return pattern_flags.pattern
endfunction

function! s:HighlightSearchAsPattern(search)
  if a:search == ''
    return
  endif

  call clearmatches()
  let pattern = s:GetFindInFilesSearchPattern(a:search)
  execute 'silent! 2match InputChar /'.pattern.'/'
  execute 'silent! 1match FirstColumn /^\S*/'
endfunction

function! s:TransformPatternOneByOne(pattern)
  let chars = split(a:pattern, '\zs')
  let idx = 0
  for char in chars
    " \b -> \W for rg/ag
    call s:ReplaceEscapedChar(chars, idx, char, ['b'], ['W'])
    let idx += 1
  endfor

  return join(chars, '')
endfunction

function! s:AddBackslashIfNot(chars,idx, char, target)
  let idx = a:idx

  if count(a:target, a:char) > 0 && idx > 0
    if a:chars[idx-1] != '\'
      let a:chars[idx] = '\'.a:chars[idx]
    endif
  endif
endfunction

" For example:
" target ['(', ')', '|']) means ( -> \(, \( -> (, ...,
function! s:ReverseBackslash(chars, idx, char, target)
  let idx = a:idx

  if count(a:target, a:char) > 0 && idx > 0
    if a:chars[idx-1] == '\'
      let a:chars[idx-1] = ''
    else
      let a:chars[idx] = '\'.a:chars[idx]
    endif
  endif
endfunction

function! s:ReplaceEscapedChar(chars, idx, char, from, to)
  let idx = a:idx

  let char_idx = index(a:from, a:char)
  if char_idx != -1 && idx > 0
    if a:chars[idx-1] == '\'
      let a:chars[idx] = a:to[char_idx]
    endif
  endif
endfunction

function! s:HighlightInputChars(input)
  call clearmatches()
  for lnum in range(1, line('$'))
    let pos = s:GetMatchPos(lnum, a:input)
    if len(pos) > 0
      for i in range(0, len(pos), 8)
        call matchaddpos('InputChar', pos[i:i+7])
      endfor
    endif
  endfor
endfunction

function! s:GetMatchPos(lnum, input)
  if empty(a:input)
    return []
  endif

  let search = split(a:input, '\zs')
  let pos = []
  let start = 0

  let first_col_str = matchstr(getline(a:lnum), '^\S*')
  let first_col = split(first_col_str, '\zs')

  " Try first col full match
  let full_match = match(first_col_str, a:input)
  if full_match > 0
    for start in range(full_match + 1, full_match + len(a:input))
      call add(pos, [a:lnum, start])
    endfor
  endif

  " Try first col
  if start == 0
    for char in search
      let start = index(first_col, char, start, 1) + 1
      if start == 0
        let pos = []
        break
      endif

      call add(pos, [a:lnum, start])
    endfor
  endif

  " No match in first col, try second col
  if start == 0
    let first_length = len(first_col)
    let second_col_str = matchstr(getline(a:lnum), '\s\+.*')
    let second_col = split(second_col_str, '\zs')
    let second_index = 0
  endif

  " Try second col full match
  if start == 0
    let full_match = match(second_col_str, a:input)
    if full_match > 0
      for start in range(full_match + 1, full_match + len(a:input))
        call add(pos, [a:lnum, start + first_length])
      endfor
    endif
  endif

  " Try second col
  if start == 0
    for char in search
      let start = index(second_col, char, start, 1) + 1
      if start == 0
        break
      endif

      call add(pos, [a:lnum, start + first_length])
      let second_index += 1
    endfor
  endif

  " Try first col after second col
  if start == 0 && second_index > 0
    for char in search[second_index:]
      let start = index(first_col, char, start, 1) + 1

      if start == 0
        break
      endif

      call add(pos, [a:lnum, start])
    endfor
  endif

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
  call s:AdjustConfig()
endfunction
