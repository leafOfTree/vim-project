if exists('g:vim_project_loaded') | finish | endif

function! s:Prepare()
  let s:name = 'vim-project'
  let s:project_list_prefix = 'Open a project:'
  let s:search_files_prefix = 'Search files by name:'
  let s:find_in_files_prefix = 'Find in files:'
  let s:search_replace_separator = ' => '
  let s:find_in_files_show_max = 200
  let s:find_in_files_stop_max = 100000
  let s:search_files_sort_max = 1000
  let s:list_history = {}
  let s:laststatus_save = &laststatus
  let s:initial_height = 0
  let s:head_file_job = 0
  let s:project = {}
  let s:branch = ''
  let s:branch_default = ''
  let s:reloading_project = 0
  let s:loading_on_vim_enter = 0
  let s:start_project = {}
  let s:start_buf = ''
  let s:dismissed_find_replace = 0
  let s:update_timer = 0
  let s:sourcing_file = 0
  let s:init_input = ''
  let s:list_buffer = 'vim_project_list'
  let s:nerdtree_tmp = 'vim_project_nerdtree_tmp'
  let s:is_win_version = has('win32') || has('win64')
  let s:view_index = 0
  let s:run_tasks_output_rows = 10

  let s:note_prefix = '- '
  let s:column_pattern = '\S*\(\s\S\+\)*'
  let s:note_column_pattern = '\(\s\{2,}'.s:note_prefix.s:column_pattern.'\)\?'
  let s:first_column_pattern = '^'.s:column_pattern
  let s:second_column_pattern = '\s\{2,}[^- ]'.s:column_pattern

  let s:add_file = 'project.add.vim'
  let s:ignore_file = 'project.ignore.vim'
  let s:init_file = 'init.vim'
  let s:quit_file = 'quit.vim'

  let s:default = {
        \'config_home':                   '~/.vim/vim-project-config',
        \'project_base':                  ['~'],
        \'use_session':                   0,
        \'open_root_when_use_session':    0,
        \'check_branch_when_use_session': 0,
        \'project_root':                 './',
        \'auto_load_on_start':            0,
        \'include':                       ['./'],
        \'search_include':                [],
        \'find_in_files_include':         [],
        \'exclude':                       ['.git', 'node_modules', '.DS_Store'],
        \'search_exclude':                [],
        \'find_in_files_exclude':         [],
        \'auto_detect':                   'no',
        \'auto_detect_file':              ['.git', '.svn'],
        \'project_views':                 [],
        \'file_mappings':                 {},
        \'tasks':                         [],
        \'debug':                         0,
        \}

  let s:local_config_keys = [
        \'include',
        \'search_include',
        \'find_in_files_include',
        \'exclude',
        \'search_exclude',
        \'find_in_files_exclude',
        \'project_root',
        \'file_mappings',
        \'tasks',
        \'use_session',
        \'open_root_when_use_session',
        \'check_branch_when_use_session',
        \]

  let s:default.list_mappings = {
        \'open':                 "\<cr>",
        \'open_split':           "\<c-s>",
        \'open_vsplit':          "\<c-v>",
        \'open_tabedit':         "\<c-t>",
        \'close_list':           "\<esc>",
        \'clear_char':           ["\<bs>", "\<c-a>"],
        \'clear_word':           "\<c-w>",
        \'clear_all':            "\<c-u>",
        \'prev_item':            ["\<c-k>", "\<up>"],
        \'next_item':            ["\<c-j>", "\<down>"],
        \'first_item':           ["\<c-h>", "\<left>"],
        \'last_item':            ["\<c-l>", "\<right>"],
        \'scroll_up':            "\<c-p>",
        \'scroll_down':          "\<c-n>",
        \'prev_view':            "\<s-tab>",
        \'next_view':            "\<tab>",
        \'paste':                "\<c-b>",
        \'replace_prompt':       "\<c-r>",
        \'replace_dismiss_item': "\<c-d>",
        \'replace_confirm':      "\<c-y>",
        \'stop_task':            "\<c-q>",
        \'switch_to_list':       "\<c-o>",
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
  let s:projects_error = []
  let s:projects_ignore = []
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

  if has_key(user, 'list_mappings')
    let user.list_mappings = s:MergeUserConfigIntoDefault(
          \user.list_mappings,
          \default.list_mappings)
  endif

  for key in keys(default)
    if has_key(user, key)
      let default[key] = user[key]
    endif
  endfor

  return default
endfunction

function! s:InitConfig()
  let s:config = deepcopy(s:GetConfig('config', {}))
  let s:config_home = expand(s:config.config_home)
  let s:open_root_when_use_session = s:config.open_root_when_use_session
  let s:check_branch_when_use_session = s:config.check_branch_when_use_session
  let s:use_session = s:config.use_session
  let s:project_root = s:config.project_root
  let s:project_base = s:RemoveListTrailingSlash(s:config.project_base)
  let s:include = s:config.include
  let s:search_include = s:config.search_include
  let s:find_in_files_include = s:config.find_in_files_include
  let s:exclude = s:config.exclude
  let s:search_exclude = s:config.search_exclude
  let s:find_in_files_exclude = s:config.find_in_files_exclude

  " options: 'always', 'ask', 'no'
  let s:auto_detect = s:config.auto_detect

  let s:auto_detect_file = s:config.auto_detect_file
  let s:auto_load_on_start = s:config.auto_load_on_start
  let s:project_views = s:config.project_views
  let s:file_mappings = s:config.file_mappings
  let s:list_mappings = s:config.list_mappings
  let s:open_types = s:config.file_open_types
  let s:tasks = s:config.tasks
  let s:debug = s:config.debug
endfunction

function! s:ExtendUniqueItems(list1, list2)
  for item in a:list2
    if count(a:list1, item) == 0
      call add(a:list1, item)
    endif
  endfor
endfunction

function! s:AdjustConfig()
  call s:ExtendUniqueItems(s:search_include, s:include)
  call s:ExtendUniqueItems(s:find_in_files_include, s:include)
  call s:ExtendUniqueItems(s:search_exclude, s:exclude)
  call s:ExtendUniqueItems(s:find_in_files_exclude, s:exclude)

  let s:search_include = s:AdjustIncludeExcludePath(s:search_include, ['.'])
  let s:find_in_files_include =
        \s:AdjustIncludeExcludePath(s:find_in_files_include, ['.'])

  let s:search_exclude = s:AdjustIncludeExcludePath(s:search_exclude, [])
  let s:find_in_files_exclude =
        \s:AdjustIncludeExcludePath(s:find_in_files_exclude, [])
endfunction

function! s:RemoveListTrailingSlash(list)
  call map(a:list, {_, val -> s:RemovePathTrailingSlash(val)})
  return a:list
endfunction

function! s:RemoveListHeadingDotSlash(list)
  call map(a:list, {_, val -> s:RemovePathHeadingDotSlash(val)})
  return a:list
endfunction

function! s:AdjustIncludeExcludePath(paths, default)
  let paths = a:paths
  if empty(paths)
    let paths = a:default
  endif
  call s:RemoveListTrailingSlash(paths)
  call s:RemoveListHeadingDotSlash(paths)
  return paths
endfunction

function! s:GetAddArgs(args)
  let args = split(a:args, ',\s*\ze{')
  let path = args[0]
  let option = len(args) > 1 ? json_decode(args[1]) : {}
  return [path, option]
endfunction

function! project#AddProject(args)
  let [path, option] = s:GetAddArgs(a:args)
  let [error, project] = s:AddProject(path, option)
  if error || s:sourcing_file
    return 
  endif

  call s:OpenProject(project)

  let save_path = s:ReplaceHomeWithTide(s:GetFullPath(path))
  if !empty(option)
    call s:SaveToAddFile(save_path.', '.json_encode(option))
  else
    call s:SaveToAddFile(save_path)
  endif
  redraw
  let message = 'Added '.path
        \.'. Config created at '.s:ReplaceHomeWithTide(s:config_home)
  call s:Info(message)
endfunction

function! s:AddProject(path, ...)
  let fullpath = s:GetFullPath(a:path)
  let option = a:0 > 0 ? a:1 : {}

  let hasProject = s:ProjectExistsWithSameFullPath(
        \fullpath,
        \s:projects
        \)
  if hasProject
    if !s:sourcing_file
      call s:Info('Already has '.a:path)
    endif
    return [1, v:null]
  endif

  let name = matchstr(fullpath, '/\zs[^/]*$')
  let path = substitute(fullpath, '/[^/]*$', '', '')
  let note = get(option, 'note', '')
  if !empty(note)
    let note = s:note_prefix.note
  endif

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
    if !s:sourcing_file
      call s:Warn('Directory not found: '.s:ReplaceHomeWithTide(fullpath))
    endif
    call insert(s:projects_error, project)
    return [1, v:null]
  endif

  call s:InitProjectConfig(project)
  call add(s:projects, project)
  return [0, project]
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

function! s:ReplaceBackSlash(val)
  if s:is_win_version
    return substitute(a:val, '\', '/', 'g')
  else
    return a:val
  endif
endfunction

function! s:SetSlashBasedOnOS(val)
  if s:is_win_version
    return substitute(a:val, '/', '\', 'g')
  else
    return substitute(a:val, '\', '/', 'g')
  endif
endfunction

function! s:ReplaceHomeWithTide(path)
  let home = escape(expand('~'), '\')
  let home2 = s:ReplaceBackSlash(expand('~'))

  let result = a:path
  let result = substitute(result, '^'.home, '~', '')
  let result = substitute(result, '^'.home2, '~', '')
  return result
endfunction

function! s:RemoveProjectPath(path)
  let result = substitute(a:path, $vim_project, '', '')
  if result != a:path
    let result = substitute(result, '^/', '', '')
  endif
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

function! s:RemovePathTrailingSlash(path)
  return substitute(a:path, '[\/\\]$', '', '')
endfunction

function! s:RemovePathHeadingDotSlash(path)
  return substitute(a:path, '^\.[\/]', '', '')
endfunction

function! s:GetFullPath(path)
  let path = a:path
  let path = s:RemovePathTrailingSlash(path)
  let path = s:GetAbsolutePath(path)
  let path = substitute(expand(path), '\', '\/', 'g')
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
    let base_list = s:GetProjectBase()
    for base in base_list
      let full_path = base.'/'.path
      if isdirectory(expand(full_path))
        return full_path
      endif
    endfor
  endif
  return path
endfunction

function! s:GetProjectBase()
  return insert(copy(s:project_base), getcwd())
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
          \'""""""""""""""""""""""""""""""""""""""""""""""',
          \'',
          \'" Local config. Those of list types extend global config. Others override',
          \'" let g:vim_project_local_config = {',
          \'"   \''include'': [''./''],',
          \'"   \''exclude'': [''.git'', ''node_modules'', ''.DS_Store''],',
          \'"   \''tasks'': [',
          \'"     \{',
          \'"       \''name'': ''start'',',
          \'"       \''cmd'': ''npm start''',
          \'"     \}',
          \'"   \],',
          \'"   \''project_root'': ''./'',',
          \'"   \''use_session'': 0,',
          \'"   \''open_root_when_use_session'': 0,',
          \'"   \''check_branch_when_use_session'': 0,',
          \'"   \}',
          \'',
          \'" file_mappings extend global config',
          \'" let g:vim_project_local_config.file_mappings = {',
          \'"   \''r'': ''README.md'',',
          \'"   \''l'': [''html'', ''css'']',
          \'"   \}',
          \'',
          \'let g:vim_project_local_config = {',
          \'\}',
          \'let g:vim_project_local_config.file_mappings = {',
          \'\}',
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

function! s:Info(msg, ...)
  echom '['.s:name.'] '.a:msg
endfunction

function! s:InfoEcho(msg)
  echo '['.s:name.'] '.a:msg
endfunction

function! s:InfoHl(msg)
  echohl Type | echom '['.s:name.'] '.a:msg | echohl None
endfunction

function! s:Warn(msg)
  redraw
  echohl WarningMsg
  echom '['.s:name.'] '.a:msg
  echohl None
endfunction

function! s:DebugWarn(msg)
  if s:debug
    call s:Warn(a:msg)
  endif
endfunction

function! s:GetProjectConfigPath(config_home, project)
  let id = a:project.path
  let id = s:ReplaceHomeWithTide(id)
  let id = substitute(id, '[/:]', '_', 'g')
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
    let base_list = s:GetProjectBase()
    let head = join(base_list, ',').'/'.head
    let tail = a:path
  else
    let tail = s:GetPathTail(a:path)
  endif
  let dirs = split(globpath(head, '*'), "\n")
  call map(dirs,
        \{_, val -> s:ReplaceBackSlash(val)})

  call filter(dirs,
        \{_, val -> match(s:GetPathTail(val), tail) != -1})
  call filter(dirs,
        \{_, val -> isdirectory(expand(val))})
  call map(dirs,
        \{_, val -> s:ReplaceHomeWithTide(val)})

  " If only one found, append a '/' to its end to show difference
  if len(dirs) == 1 && isdirectory(expand(dirs[0]))
    let dirs[0] = dirs[0].'/'
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
  let g:vim_project_loaded = 1
  call s:Main()
  call s:SourcePluginConfigFiles()
  call s:WatchOnBufEnter()
endfunction

function! project#checkVersion()
  return s:CheckVersion()
endfunction

function! s:CheckVersion()
  if exists('g:vim_project_config')
        \&& type(g:vim_project_config) == type('')
    let message1 =  'Hey, it seems that you just upgraded. Please configure `g:vim_project_config` as a dict'
    let message2 =  'For details, please check README.md or https://github.com/leafOfTree/vim-project'
    echom '[vim-project] '.message1
    echom '[vim-project] '.message2
    return 1
  endif

  return 0
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

function! s:SaveToAddFile(path)
  let cmd = 'Project '.a:path
  let file = s:config_home.'/'.s:add_file
  call writefile([cmd], file, 'a')
endfunction

function! s:RemoveItemInProjectAddConfig(path)
  let file = s:config_home.'/'.s:add_file
  let adds = readfile(file)
  let idx = s:GetItemIndexInProjectAddConfig(adds, a:path)
  if idx < len(adds)
    call remove(adds, idx)
    call writefile(adds, file)
  endif
endfunction

function! s:RenamePathInProjectAddConfig(path, new_fullpath)
  let file = s:config_home.'/'.s:add_file
  let adds = readfile(file)

  let target = s:ReplaceHomeWithTide(a:path)
  let target_pat = '\s'.escape(target, '~\/').'\($\|\/\)'
  let idx = 0
  for line in adds
    if s:Include(line, target_pat)
      let adds[idx] = substitute(line, target_pat, ' '.a:new_fullpath, '')
    endif
    let idx += 1
  endfor
  call writefile(adds, file)
endfunction

function! s:GetItemIndexInProjectAddConfig(adds, path)
  let target = s:ReplaceHomeWithTide(a:path)
  let target_pat = '\s'.escape(target, '~\/').',\?'
  let idx = 0
  for line in a:adds
    if s:Include(line, target_pat)
      break
    endif
    let idx += 1
  endfor

  return idx
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
      autocmd BufEnter * ++once call s:SetStartProjectOnBufEnter()
      autocmd VimEnter * ++once call s:AutoloadOnVimEnter()
    endif
    if s:auto_detect != 'no'
      autocmd BufEnter * call s:AutoDetectProject()
    endif
  augroup END
endfunction

function! s:WatchOnInitFileChange()
  autocmd BufWritePost $vim_project_config/init.vim call s:Info('Config Reloaded')
  autocmd BufWritePost $vim_project_config/init.vim call s:SourceInitFile()
endfunction

function! s:UnwatchOnInitFileChange()
  autocmd! BufWritePost $vim_project_config/init.vim
endfunction

function! s:SetStartProjectOnBufEnter()
  if v:vim_did_enter
    return
  endif

  let buf = expand('<amatch>')
  let project = s:GetProjectByPath(s:projects, buf)

  if empty(project)
    return
  endif
  let s:start_buf = buf
  let s:start_project = project
endfunction

function! s:DoBufEvent()
  doautoall BufRead
  doautoall BufEnter
endfunction

function! s:AutoloadOnVimEnter()
  if empty(s:start_project)
    return
  endif

  let s:loading_on_vim_enter = 1
  execute 'ProjectOpen '.s:start_project.name
  let s:loading_on_vim_enter = 0
  call s:DoBufEvent()
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
  call s:SaveToAddFile(a:path)
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

function! project#ListProjects()
  let s:prefix = s:project_list_prefix
  let s:list_type = 'PROJECTS'
  call s:PrepareListBuffer()
  let Init = function('s:ProjectListBufferInit')
  let Update = function('s:ProjectListBufferUpdate')
  let Open = function('s:ProjectListBufferOpen')
  call s:RenderList(Init, Update, Open)
endfunction

function! project#SearchFiles()
  if !s:ProjectExists()
    call s:Warn('No project opened')
    return
  endif

  let s:prefix = s:search_files_prefix
  let s:list_type = 'SEARCH_FILES'
  call s:PrepareListBuffer()

  let Init = function('s:SearchFilesBufferInit')
  let Update = function('s:SearchFilesBufferUpdate')
  let Open = function('s:SearchFilesBufferOpen')
  call s:RenderList(Init, Update, Open)
endfunction

function! project#FindInFiles(...)
  if !s:ProjectExists()
    call s:Warn('No project opened')
    return
  endif

  let s:prefix = s:find_in_files_prefix
  let s:list_type = 'FIND_IN_FILES'
  call s:SetInitInput(a:000)
  call s:PrepareListBuffer()

  let Init = function('s:FindInFilesBufferInit')
  let Update = function('s:FindInFilesBufferUpdateTimer')
  let Open = function('s:FindInFilesBufferOpen')
  call s:RenderList(Init, Update, Open)
endfunction

function! project#RunTasks()
  let s:prefix = 'Run a task:'
  let s:list_type = 'RUN_TASKS'

  call s:PrepareListBuffer()
  let Init = function('s:RunTasksBufferInit')
  let Update = function('s:RunTasksBufferUpdateTimerManager')
  let Open = function('s:RunTasksBufferOpen')
  call s:RenderList(Init, Update, Open)
endfunction

function! s:RunTasksBufferInit(input)
  let max_col_width = s:max_width / 2 - 10
  call s:TabulateList(s:tasks, ['name', 'cmd'], [], 0, max_col_width)
  call s:RunTasksBufferUpdateTimerManager(a:input)
endfunction

function! s:RunTasksBufferUpdateTimerManager(input)
  call s:StopRunTasksTimer()
  call s:RunTasksBufferUpdate(a:input)
  let s:run_tasks_timer = timer_start(500, function('s:RunTasksBufferUpdateTimer', [a:input]),
        \{'repeat': -1})
endfunction

function! s:StopRunTasksTimer()
  if !s:IsRunTasksList() || !exists('s:run_tasks_timer')
    return
  endif
  call timer_stop(s:run_tasks_timer)
endfunction

function! s:RunTasksBufferUpdateTimer(input, id)
  call s:RunTasksBufferUpdate(a:input)
endfunction

function! s:GetRunTasksDisplay(tasks)
  let display = []
  let list = []

  for task in a:tasks
    if has_key(task, '__name')
      let task_row = task.__name.'  '.task.__cmd
      if has_key(task, 'cd')
        let task_row .= '  ('.task.cd.')'
      endif
      call add(display, task_row)
      call add(list, task)
    endif

    if has_key(task, 'bufnr') && task.bufnr > 0
      let status = s:GetTaskStatus(task)
      if status == ''
        continue
      endif

      let output = '  ['.status.']'
      let item = {'name': task.name, 'cmd': task.cmd, 'output': output, 'lnum': 0}
      call add(display, output)
      call add(list, item)

      if has('nvim')
        continue
      endif

      let [row, col, dict] = term_getcursor(task.bufnr)
      for idx in range(s:run_tasks_output_rows, 1, -1)
        let line = term_getline(task.bufnr, row - idx)
        let output = '  '.line
        let lnum = s:run_tasks_output_rows - idx + 1
        let item = {'name': task.name, 'cmd': task.cmd, 'output': output, 'lnum': lnum}
        call add(display, output)
        call add(list, item)
      endfor
    endif
  endfor
  return [display, list]
endfunction

function! s:RunTasksBufferUpdate(input)
  let tasks = s:FilterRunTasks(copy(s:tasks), a:input)
  let [display, list] = s:GetRunTasksDisplay(tasks)
  let s:list = list
  call s:ShowInListBuffer(display, a:input)
  call s:HighlightCurrentLine(len(display))
  call s:HighlightInputChars(a:input)
  call s:HighlightRunTasksCmdOutput()
  if a:input == ''
    redraw
  else
    call s:ShowInputLine(a:input)
  endif
endfunction

function! s:HighlightRunTasksCmdOutput()
  2match InfoRow /^\s\{2,}.*/
  match Status '\[running.*\]'
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:RunTasksBufferOpen(task, open_cmd, input)
  if s:ShouldOpenTaskBuffer(a:task)
    if a:open_cmd == ''
      return 0
    endif

    call s:OpenTaskBuffer(a:task)
    return 0
  endif

  if s:IsEmptyCmd(a:task)
    if a:open_cmd == ''
      return 0
    endif

    terminal
    if !has('nvim')
      call term_sendkeys(bufnr('%'), "cd $vim_project\<CR>")
      call term_sendkeys(bufnr('%'), "clear\<CR>")
    endif
    return 0
  endif

  return s:RunTask(a:task)
endfunction

function! s:ShouldOpenTaskBuffer(task)
  let is_output = has_key(a:task, 'output')
  let open_task_buffer = is_output
  return open_task_buffer
endfunction

function! s:IsEmptyCmd(task)
  return !has_key(a:task, 'cmd') || a:task.cmd == ''
endfunction

function! s:OpenTaskBuffer(task)
  if has('nvim')
    return
  endif

  let from_task = s:FindOriginalTask(a:task)
  execute 'sbuffer '.from_task.bufnr
endfunction

function! s:FindOriginalTask(task)
  for task in s:tasks
    if task.name == a:task.name && task.cmd == a:task.cmd
      return task
    endif
  endfor
endfunction

function! s:GetTaskStatus(task)
  if !has_key(a:task, 'bufnr')
    return ''
  endif

  if has('nvim')
    let status_code = jobwait([a:task.bufnr], 0)[0]
    if status_code == -1
      return 'running'
    else
      return 'finished'
    endif
  else
    return substitute(term_getstatus(a:task.bufnr), ',normal', '', '')
  endif
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:RunTask(task)
  let cwd = $vim_project
  if has_key(a:task, 'cd')
    let cwd .= '/'.a:task.cd
  endif

  let options = { 
        \'cwd': cwd,
        \'term_name': a:task.name,
        \'term_rows': s:run_tasks_output_rows,
        \'hidden': 1,
        \}
  let has_prev_buf = s:GetTaskStatus(a:task) != ''
  call s:StopTask(a:task)

  if has('nvim')
    enew
    set winheight=20
    let a:task.bufnr = termopen(a:task.cmd, options)
    return 0
  endif

  let index = s:GetCurrentIndex()
  let a:task.bufnr = term_start(a:task.cmd, options)

  if !has_prev_buf
    call s:UpdateOffsetByIndex(index - (s:run_tasks_output_rows + 1))
  endif
  return 1
endfunction

function! s:StopTask(task)
  let is_prev_running = s:GetTaskStatus(a:task) == 'running'
  if !is_prev_running
    if has_key(a:task, 'bufnr')
      unlet a:task.bufnr
    endif
    return
  endif

  if has('nvim')
    call jobstop(a:task.bufnr)
  else
    execute 'bdelete! '.a:task.bufnr
  endif
  unlet a:task.bufnr
endfunction

function! s:StopTaskHandler(input)
  let index = s:GetCurrentIndex()

  let current_task = s:GetTarget()
  if s:IsTaskOutput(current_task)
    let index = index - current_task.lnum - 1
  endif
  let task = s:FindOriginalTask(current_task)
  call s:StopTask(task)
  call s:RunTasksBufferUpdate(a:input)
  call s:UpdateOffsetByIndex(index)
endfunction

function! s:IsTaskOutput(task)
  return has_key(a:task, 'lnum')
endfunction

function! s:FilterRunTasks(tasks, filter)
  let regexp_filter = join(split(a:filter, '\zs'), '.*')

  for task in a:tasks
    let task._match_type = ''
    let task._match_index = -1

    let match_index = match(task.name, regexp_filter)
    if match_index != -1
      " Prefer exact match. If not, add 10 to match_index
      if len(a:filter) > 1 && count(tolower(task.name), a:filter) == 0
        let match_index = match_index + 10
      endif
      let task._match_type = 'name'
      let task._match_index = match_index
    endif

    if match_index == -1
      let match_index = match(task.cmd, regexp_filter)
      if match_index != -1
        let task._match_type = 'cmd'
        let task._match_index = match_index
      endif
    endif
  endfor

  let result = filter(a:tasks, { _, val -> val._match_type != '' })
  call sort(result, 's:SortRunTasks')
  return result
endfunction

function! s:SortRunTasks(a1, a2)
  let type1 = a:a1._match_type
  let type2 = a:a2._match_type
  let index1 = a:a1._match_index
  let index2 = a:a2._match_index

  if type1 == 'name' && type2 != 'name'
    return 1
  endif

  if type1 == type2
    return index2 - index1
  endif

  return -1
endfunction

function! s:SetInitInput(args)
  if len(a:args) == 2
    let input = a:args[0]
    let range = a:args[1]

    if !empty(input)
      let s:init_input = input
      return
    endif

    if range > 0
      let saved = @z
      normal! gv"zy
      let s:init_input = @z
      let @z = saved
      return
    endif
  endif
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
  call s:StopRunTasksTimer()

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
  setlocal filetype=vimprojectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set laststatus=0

  if s:IsFindInFilesList()
    let s:first_column_pattern = '^'.s:column_pattern
    let s:second_column_pattern = '\s\{2,}[^- ]'.s:column_pattern
    highlight link FirstColumn Keyword
    highlight link SecondColumn Normal
  elseif s:IsRunTasksList()
    let s:first_column_pattern = '^'.s:column_pattern
    let s:second_column_pattern = '\s\{2,}[^- ]'.s:column_pattern
    highlight link FirstColumn Keyword
    highlight link SecondColumn Comment
    highlight link Status Constant
    " Linking InfoRow to Normal does not work when overriding other syntax
    if has('nvim')
      highlight link InfoRow Normal
    else
      let normal_hl = hlget('Normal')
      let normal_hl[0].name = 'InfoRow'
      call hlset(normal_hl)
    endif
    call s:HighlightRunTasksCmdOutput()
  else
    let s:first_column_pattern = '^'.s:column_pattern.s:note_column_pattern
    let s:second_column_pattern = '\s\{2,}[^- ]'.s:column_pattern

    highlight link FirstColumn Normal
    highlight link SecondColumn Comment
  endif

  syntax clear
  execute 'syntax match FirstColumn /'.s:first_column_pattern.'/'
  execute 'syntax match SecondColumn /'.s:second_column_pattern.'/'
  execute 'syntax match InfoRow /^\s\{2,}.*/'

  highlight link ItemSelected CursorLine
  highlight! link SignColumn Noise
  highlight link InputChar Constant

  call s:HighlightWithBgBasedOn('Comment', 0, 0, 'BeforeReplace')
  call s:HighlightWithBgBasedOn('Function', 0, 'bold', 'AfterReplace')

  sign define selected text=> texthl=ItemSelected linehl=ItemSelected
endfunction

function! s:HighlightWithBgBasedOn(base_group, bg_group, attr, new_group)
  let ctermfg = s:GetArgValue(a:base_group, 'fg', 'cterm')
  let ctermbg = s:GetArgValue(a:base_group, 'bg', 'cterm')
  let guifg = s:GetArgValue(a:base_group, 'fg', 'gui')
  let guibg = s:GetArgValue(a:base_group, 'bg', 'gui')

  if !empty(a:base_group)
    let ctermbg_default = s:GetArgValue(a:bg_group, 'bg', 'cterm')
    let guibg_default = s:GetArgValue(a:bg_group, 'bg', 'gui')
    if empty(ctermbg)
      let ctermbg = ctermbg_default
    endif

    if empty(guibg)
      let guibg = guibg_default
    endif
  endif

  let highlight_cmd = 'highlight '.a:new_group

  if !empty(a:attr)
    let highlight_cmd .= ' term='.a:attr.' cterm='.a:attr.' gui='.a:attr
  endif

  if !empty(ctermfg)
    let highlight_cmd .= ' ctermfg='.ctermfg
  endif
  if !empty(ctermbg)
    let highlight_cmd .= ' ctermbg='.ctermbg
  endif

  if !empty(guifg)
    let highlight_cmd .= ' guifg='.guifg
  endif
  if !empty(guibg)
    let highlight_cmd .= ' guibg='.guibg
  endif

  execute highlight_cmd
endfunction

function! s:GetArgValue(name, what, mode)
  return synIDattr(synIDtrans(hlID(a:name)), a:what, a:mode)
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
  normal! G"_dd
  normal! gg
  normal! G
endfunction

function! s:AddToListBuffer(display)
  normal! gg"_dG
  if len(a:display) > 0
    call append(0, a:display)
  endif
endfunction

function! s:AdjustHeight(length, input)
  if (a:length == 0 && a:input == '') || a:length > s:max_height
    let s:initial_height = s:max_height
  elseif a:input == '' && s:initial_height == 0
    let s:initial_height = a:length
  elseif a:length > s:initial_height && a:length < s:max_height
    let s:initial_height = a:length
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

function! s:FilterProjectsList(list, filter)
  let regexp_filter = join(split(a:filter, '\zs'), '.*')

  for item in a:list
    let item._match_type = ''
    let item._match_index = -1

    " Filter by name
    let match_index = match(item.name, regexp_filter)
    if match_index != -1
      " Prefer exact match. If not, add 10 to match_index
      if len(a:filter) > 1 && count(tolower(item.name), a:filter) == 0
        let match_index = match_index + 10
      endif

      let item._match_type = 'name'
      let item._match_index = match_index
    endif

    " Filter by note
    if match_index == -1
      if has_key(item.option, 'note')
        let match_index = match(item.option.note, regexp_filter)
        if match_index != -1
          let item._match_type = 'note'
          let item._match_index = match_index
        endif
      endif
    endif

    " Filter by path
    if match_index == -1
      let match_index = match(item.path, regexp_filter)
      if match_index != -1
        let item._match_type = 'path'
        let item._match_index = match_index
      endif
    endif

    " Filter by path+name
    if match_index == -1
      let match_index = match(item.path.item.name, regexp_filter)
      if match_index != -1
        let item._match_type = 'path_name'
        let item._match_index = match_index
      endif
    endif
  endfor

  " Try matching name and note. If none, then match path, etc.
  let result = filter(copy(a:list), { _, val -> val._match_type == 'name' || val._match_type == 'note' })
  if len(result) == 0
    let result = filter(a:list, { _, val -> val._match_type != '' })
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
  let max = len(s:project_views)
  let s:view_index = s:view_index < max - 1 ? s:view_index + 1 : 0
endfunction

function! s:PreviousView()
  let max = len(s:project_views)
  let s:view_index = s:view_index > 0 ? s:view_index - 1 : max - 1
endfunction

function! s:FilterProjectsByView(projects)
  let max = len(s:project_views)
  if s:view_index >= 0 && s:view_index < max
    let view = s:project_views[s:view_index]
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

  if a:filter == ''
    call sort(projects, 's:SortInauguralProjectsList')
  else
    let projects = s:FilterProjectsList(projects, a:filter)
  endif

  return projects
endfunction

function! s:SortInauguralProjectsList(a1, a2)
  return a:a1.name < a:a2.name ? 1 : -1
endfunction

function! s:AddRightPadding(string, length)
  let string = a:string
  let padding = repeat(' ', a:length - len(string) + 1)
  let string .= padding
  return string
endfunction

function! project#OutputProjects(...)
  let filter = a:0>0 ? a:1 : ''
  let projects = s:projects
  let projects = s:FilterProjects(projects, filter)
  echo projects
endfunction

function! s:TabulateList(list, keys, no_limit_keys, min_col_width, max_col_width)
  " Init max width of each column
  let max = {}

  " Get max width of each column
  for item in a:list
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
    for item in a:list
      for key in a:keys
        if has_key(item, key)
          let value = item['__'.key]
          if len(value) > a:max_col_width && count(a:no_limit_keys, key) == 0
            let value = value[0 : a:max_col_width-2].'..'
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
  for item in a:list
    for key in a:keys
      if has_key(item, key)
        let max_width = max([max[key], a:min_col_width])
        let item['__'.key] = s:AddRightPadding(item['__'.key], max_width)
      endif
    endfor
  endfor
endfunction

function! s:GetListCommand(char)
  let command = ''
  for [key, value] in items(s:list_mappings)
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
  call s:TabulateList(s:projects, ['name', 'path', 'note'], ['note'], 0, max_col_width)
  call s:ProjectListBufferUpdate(a:input)
endfunction

function! s:ProjectListBufferUpdate(input)
  let s:list = s:FilterProjects(copy(s:projects), a:input)
  let display = s:GetProjectsDisplay(s:list)
  call s:ShowInListBuffer(display, a:input)
  call s:HighlightCurrentLine(len(display))
  call s:HighlightInputChars(a:input)
endfunction

function! s:ProjectListBufferOpen(project, open_cmd, input)
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

function! s:DecorateSearchFilesDisplay(list, display)
  if s:IsListMore(a:list)
    let a:display[0] .= '...more'
  endif

  let recent_index = s:GetRecentIndex(a:list)
  if recent_index != -1
    let a:display[recent_index] .= ''
  endif
endfunction

function! s:GetRecentIndex(list)
  let index = 0
  for item in a:list
    if has_key(item, 'recent') && item.recent
      return index
    endif
    let index += 1
  endfor

  return -1
endfunction

function! s:GetSearchFilesDisplay(list)
  let display = map(copy(a:list), function('s:GetSearchFilesDisplayRow'))
  call s:DecorateSearchFilesDisplay(a:list, display)
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
  call s:SortSearchFilesList(oldfiles, a:input)

  return oldfiles
endfunction

function! s:GetOldFiles()
  let oldfiles = copy(v:oldfiles)

  call s:AddBuffers(oldfiles)
  return oldfiles
endfunction

function! s:AddBuffers(oldfiles)
  let bufs = getbufinfo({'buflisted': 1})
  call sort(bufs, {buf1, buf2 -> buf1.lastused - buf2.lastused})
  for buf in bufs
    let bufname = s:ReplaceHomeWithTide(buf.name)
    call insert(a:oldfiles, bufname)
  endfor
endfunction

function! s:FilterOldFilesByPath(oldfiles)
  let project_dir = s:SetSlashBasedOnOS(s:ReplaceHomeWithTide($vim_project.'/'))
  call filter(a:oldfiles, {_, val -> count(val, project_dir) > 0 })

  let search_exclude = copy(s:search_exclude)
  call map(search_exclude, {_, val -> project_dir.val})
  call filter(a:oldfiles, {_, val -> !s:IsPathStartWithAny(val, search_exclude)})

  call map(a:oldfiles, {_, val -> fnamemodify(val, ':p')})
  call filter(a:oldfiles, {_, val ->
        \ count(['ControlP', ''], fnamemodify(val, ':t')) == 0
        \ && (filereadable(val) || isdirectory(val))
        \})


  let project_dir_pat = escape(fnamemodify(project_dir, ':p'), '\')
  call map(a:oldfiles, {_, val -> substitute(val, project_dir_pat, './', '')})
endfunction

function! s:IsPathStartWithAny(fullpath, starts)
  for start in a:starts

    if s:StartWith(a:fullpath, start)
      return 1
    endif
  endfor

  return 0
endfunction

function! s:StartWith(string, search)
  return a:string[0:len(a:search)-1] ==# a:search
endfunction

function! s:FilterOldFilesByInput(oldfiles, input)
  let pattern = join(split(a:input, '\zs'), '.*')
  call filter(a:oldfiles,
        \{_, val -> val.file =~ pattern})
endfunction

function! s:GetFilesByFind()
  let include = join(s:search_include, ' ')

  let search_exclude = copy(s:search_exclude)
  let exclude_string = join(map(search_exclude, {_, val -> '-name "'.val.'"'}), ' -o ')
  let exclude = '\( '.exclude_string.' \) -prune -false -o '

  let filter = '-ipath "*"'
  let cmd = 'find '.include.' -mindepth 1 '.exclude.filter
  let result = s:RunShellCmd(cmd)
  return result
endfunction

function! s:GetFilesByFd()
  let include = join(s:search_include, ' ')

  let search_exclude = copy(s:search_exclude)
  let exclude = join(map(search_exclude, {_, val -> '-E "'.val.'"'}), ' ')

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

function! s:GetSearchFilesByDirectory(val, filter)
  let path = a:val.path
  let file = a:val.file
  let full_path = $vim_project.'/'.path.'/'.file

  return isdirectory(full_path) && file =~ a:filter
endfunction

function! s:GetSearchFilesByFilterForDirectory(input)
  let list = []
  let filter = substitute(a:input, '/$', '', '')
  let list = filter(copy(s:list_initial_result), {_, val -> s:GetSearchFilesByDirectory(val, filter)})

  if len(list) < s:max_height
    call s:SortSearchFilesList(list, filter)

    let filter_fuzzy = join(split(filter, '\zs'), '.*')
    let list_extra = filter(copy(s:list_initial_result), {_, val -> s:GetSearchFilesByDirectory(val, filter_fuzzy)})
    call s:SortSearchFilesList(list_extra, filter)
    let list += list_extra
  endif

  return list
endfunction

function! s:GetSearchFilesByFilterForFullpath(input)
  let filter_origin = a:input
  let list = []
  " Match file
  if len(a:input) < 3
    let filter_start = '^'.filter_origin
    let list = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter_start})
  endif

  if len(list) < s:max_height
    let list = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter_origin})
    call s:SortSearchFilesList(list, a:input)
  endif

  if len(list) < s:max_height
    let filter_fuzzy = join(split(a:input, '\zs'), '.*')
    let list_extra = filter(copy(s:list_initial_result), {_, val -> val.file =~ filter_fuzzy})
    call s:SortSearchFilesList(list_extra, a:input)
    let list += list_extra
  endif

  " Match path and file if list is short
  if len(list) < s:max_height
    let list_extra = filter(copy(s:list_initial_result), {_, val -> val.path.val.file =~ filter_origin})
    let list += list_extra
  endif

  " Fuzzy match path and file if list is short
  if len(list) < s:max_height
    let list_extra = filter(copy(s:list_initial_result), {_, val -> val.path.val.file =~ filter_fuzzy})
    let list += list_extra
  endif
  return list
endfunction

function! s:GetSearchFilesByFilter(input)
  if a:input =~ '[^\\]/$'
    " Match directory only
    return s:GetSearchFilesByFilterForDirectory(a:input)
  else
    " Match both directory and filename
    return s:GetSearchFilesByFilterForFullpath(a:input)
  endif
endfunction

function! s:GetSearchFiles(input)
  let oldfiles = s:GetSearchFilesByOldFiles(a:input)
  let search_list = s:GetSearchFilesResultList(a:input)

  let files = oldfiles + search_list

  let max_length = s:max_height - 1
  let files = files[0:max_length*3]
  call s:UniqueList(files)

  if len(files) > max_length
    let files = files[0:max_length]
    let files[-1].more = 1
  endif
  if len(oldfiles) > 0
    let oldfiles[len(oldfiles) - 1].recent = 1
  endif

  call reverse(files)
  return files
endfunction

function! s:MapSearchFiles(list)
  call map(a:list, {idx, val ->
        \{
        \'file': fnamemodify(val, ':t'),
        \'path': fnamemodify(val, ':h:s+\./\|\.\\\|^\.$++'),
        \}})
endfunction

function! s:SortSearchFilesList(list, input)
  " For performance purpose, skip sorting if there are too many items
  if len(a:list) > s:search_files_sort_max
    return
  endif

  if !empty(a:input) && len(a:list) > 0
    call sort(a:list, function('s:SortFilesList', [a:input]))
  endif
endfunction

function! s:GetSearchFilesResult(input)
  let files = s:GetSearchFiles(a:input)
  let min_col_width = s:max_width / 4
  let max_col_width = s:max_width / 8 * 5
  call s:TabulateList(files, ['file', 'path'], ['path'], min_col_width, max_col_width)
  let display = s:GetSearchFilesDisplay(files)
  return [files, display]
endfunction

function! s:SearchFilesBufferInit(input)
  return s:SearchFilesBufferUpdate(a:input)
endfunction

function! s:SearchFilesBufferUpdate(input)
  let [list, display] = s:GetSearchFilesResult(a:input)
  let s:input = a:input
  let s:list = list
  call s:ShowInListBuffer(display, a:input)
  call s:HighlightCurrentLine(len(display))
  call s:HighlightInputChars(a:input)
endfunction

function! s:SearchFilesBufferOpen(target, open_cmd, input)
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


  let result = s:GetGroupedList(list)
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

  let cmd = 'ag '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
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

  let cmd = 'fgrep '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
  return cmd
endfunction

function! s:GetRgCmd(pattern, flags)
  let include = copy(s:find_in_files_include)
  " Remove '.', as rg does not support '{./**}'
  call filter(include, {_, val -> val != '.'})

  if len(include)
    let include_pattern = map(include, 
          \{_, val -> val.'/**' })
    let include_arg = '-g "{'.join(include_pattern, ',').'}"'
  else
    let include_arg = '-g "{**}"'
  endif

  let exclude = copy(s:find_in_files_exclude)
  let exclude_arg = '-g "!{'.join(exclude, ',').'}"'

  let search_arg = '--line-number --no-ignore-vcs'
  if !s:Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if !s:Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'rg '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
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
  let output_len = len(output)
  let more = 0

  let replace_initially_added = s:IsReplaceInitiallyAdded(a:full_input)

  if !replace_initially_added
    if output_len > s:find_in_files_show_max
      let output = output[0:s:find_in_files_show_max]
      let more = 1
    endif
  elseif output_len > s:find_in_files_stop_max
    let error_msg = 'Error: :Stopped for too many matches, more than '
          \.s:find_in_files_stop_max
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

function! s:GetGroupedList(list)
  let joined_list = []
  let current_file = ''

  " Assume the list has already been ordered by file
  for item in a:list
    if current_file != item.file
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
  let cd_option = s:is_win_version ? '/d' : ''
  let cmd = 'cd '.cd_option.' '.$vim_project.' && '.a:cmd
  try
    let output = systemlist(cmd)
  catch
    call s:Warn('Exception on running '.a:cmd)
    call s:Warn(v:exception)
    return []
  endtry

  if v:shell_error
    if !empty(output)
      call s:DebugWarn(a:cmd)
      call s:DebugWarn(string(output))
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
  return substitute(a:search, '\\C\|\\E\|\\\@<!\\$', '', 'g')
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
    call s:HighlightCurrentLine(len(a:display))
    call s:HighlightSearchAsPattern(a:search)
    call s:HighlightReplaceChars(a:search, a:replace)
    call s:HighlighExtraInfo()
    call s:ShowInputLine(a:full_input)
  endif
endfunction

function! s:HighlighExtraInfo()
  call matchadd('Special', ' \.\.\.more$')
endfunction

function! s:FindInFilesBufferUpdate(full_input, is_init, id)
  let should_run = s:ShouldRunFindInFiles(a:full_input)
  let [search, replace] = s:ParseInput(a:full_input)
  let should_redraw = s:ShouldRedrawWithReplace(search, replace)

  if !exists('s:list')
    let s:list = []
  endif

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

function! s:HasDismissed()
  return s:dismissed_find_replace
endfunction

function! s:ResetDismissedVar()
  if s:dismissed_find_replace
    let s:dismissed_find_replace = 0
  endif
endfunction

function! s:ShouldRedrawWithReplace(input, replace)
  if s:HasDismissed()
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
  execute 'silent! 1match FirstColumn /'.s:first_column_pattern.'/'
endfunction

function! s:FindInFilesBufferOpen(target, open_cmd, input)
  let open_type = substitute(a:open_cmd, 'open_\?', '', '')
  if open_type == ''
    let open_type = 'edit'
  endif

  let file = $vim_project.'/'.a:target.file
  let lnum = has_key(a:target, 'lnum') ? a:target.lnum : 1
  execute open_type.' +'.lnum.' '.file
endfunction

function! s:ShowInputLine(input)
  redraw

  " Fix cursor flashing when in terminal
  echo ''

  echo s:prefix.' '.a:input
endfunction

function! s:ShowInitialInputLine(input, ...)
  call s:ShowInputLine(a:input)
endfunction

function! s:RenderList(Init, Update, Open)
  let input = s:InitListVariables(a:Init)
  call s:ShowInitialInputLine(input)

  let [cmd, input] = s:HandleInput(input, a:Update, a:Open)

  call s:CloseListBuffer(cmd)
  if s:IsOpenCmd(cmd)
    call s:OpenTarget(cmd, input, a:Open)
  endif
  call s:SaveListVariables(input)
  call s:ResetListVariables()
endfunction

function! s:InitListVariables(Init)
  let has_init_input = !empty(s:init_input)
  let has_history = has_key(s:list_history, s:list_type)
  if has_init_input
    let input = s:init_input
    let s:offset = 0
    let s:initial_height = s:max_height
    let s:init_input = ''
  elseif has_history
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

  " Empty input if no init and it was set from history
  if !has_init_input && has_history
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

function! s:HandleInput(input, Update, Open)
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
      elseif cmd == 'paste'
        let input .= @*
      elseif cmd == 'replace_prompt'
        let input = s:AddFindReplaceSeparator(input)
      elseif cmd == 'replace_dismiss_item'
        call s:DismissFindReplaceItem()
      elseif cmd == 'replace_confirm'
        call s:ConfirmFindReplace(input)
        break
      elseif cmd == 'switch_to_list'
        break
      elseif s:IsOpenCmd(cmd)
        if s:IsRunTasksList()
          let keep_window = s:OpenTarget('', input, a:Open)
          if !keep_window
            break
          endif
        else
          break
        endif
      elseif cmd == 'stop_task'
        call s:StopTaskHandler(input)
      else
        let input = input.char
      endif

      call a:Update(input)
      call s:ShowInputLine(input)
    endwhile
  catch /^Vim:Interrupt$/
    call s:Debug('Interrupt')
    let cmd = 'interrupt'
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
    let info_line = 'lines: '.index_line.' of '.total_lines
    let info_file = 'files: '.index_file.' of '.total_files
    redraw
    call s:InfoEcho('Replaced '.info_file.', '.info_line)
  endfor

  edit
  call timer_start(100, function('s:Info', ['Replaced '.info_file.', '.info_line]))
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

function! s:IsFindInFilesList()
  return s:list_type == 'FIND_IN_FILES'
endfunction

function! s:IsSearchFilesList()
  return s:list_type == 'SEARCH_FILES'
endfunction

function! s:IsRunTasksList()
  return s:list_type == 'RUN_TASKS'
endfunction

function! s:SaveListVariables(input)
  if !s:IsFindInFilesList()
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

  if index >= 0 && index < len(s:list)
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
  call s:UpdateOffsetByIndex(index)
endfunction

function! s:UpdateOffsetByIndex(index)
  if a:index < len(s:list) - 1
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

function! s:OpenTarget(cmd, input, Open)
  let target = s:GetTarget()

  if empty(target)
    call s:Warn('No item selected')
    return
  endif

  return a:Open(target, a:cmd, a:input)
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

function! s:RenameProjectByName(name, new_name)
  let project = s:GetProjectByName(a:name, s:projects)
  if empty(project)
    let project = s:GetProjectByName(a:name, s:projects_error)
  endif

  if !empty(project)
    call s:RenameProject(project, a:new_name)

    let s:projects = []
    let s:projects_error = []
    call s:SourcePluginConfigFiles()
  endif
endfunction

function! project#RemoveProjectByName(name)
  call s:RemoveProjectByName(a:name, 0)
endfunction

function! project#RenameProjectByName(names)
  let [name, new_name] = split(a:names, ' ')
  call s:RenameProjectByName(name, new_name)
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

    redraw
    call s:Info('Reloaded')
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
    call s:Info('Opened '.new.name)
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
  call s:WatchOnInitFileChange()
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
  if a:project == s:project
    call s:QuitProject()
  endif

  let idx = index(s:projects, a:project)
  if idx >= 0
    call remove(s:projects, idx)
  else
    let idx = index(s:projects_error, a:project)
    if idx >= 0
      call remove(s:projects_error, idx)
    endif
  endif

  if idx >= 0
    call s:Info('Removed record of '. a:project.name.' ('.a:project.path.')')
    call s:SaveToPluginConfigIgnore(a:project.fullpath)
    call s:RemoveItemInProjectAddConfig(a:project.fullpath)
  endif
endfunction

function! s:RenameProject(project, new_name)
  if a:project == s:project
    call s:QuitProject()
  endif

  call s:Info('Rename '.a:project.name.' to '.a:new_name.' ('.a:project.path.')')
  let new_fullpath = a:project.path.'/'.a:new_name
  call rename(a:project.fullpath, new_fullpath)
  call s:RenamePathInProjectAddConfig(a:project.fullpath, s:ReplaceHomeWithTide(new_fullpath))

  let config_path = s:GetProjectConfigPath(s:config_home, a:project)
  let a:project.name = a:new_name
  let new_config_path = s:GetProjectConfigPath(s:config_home, a:project)
  call rename(config_path, new_config_path)
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

function! project#OpenProjectRoot()
  if s:ProjectExists()
    let path = s:GetProjectRootPath()
    if !empty(path)
      execute 'edit '.path
    endif
  endif
endfunction

function! project#OpenProjectConfig()
  if s:ProjectExists()
    let config = s:GetProjectConfigPath(s:config_home, s:project)
    execute 'tabedit '.config.'/'.s:init_file
  else
    call s:Warn('No project opened')
  endif
endfunction

function! project#OpenAllConfig()
  execute 'tabedit '.s:config_home.'/project.add.vim'
endfunction

function! project#QuitProject()
  call s:QuitProject()
endfunction

function! s:QuitProject()
  if s:ProjectExists()
    call s:Info('Quitted '.s:project.name)
    call s:SaveSession()
    call s:SourceQuitFile()
    call s:UnwatchOnInitFileChange()

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
    call s:Info('Include: '.string(s:include))
    call s:Info('Search Include: '.string(s:search_include))
    call s:Info('Find in files Include: '.string(s:find_in_files_include))
    call s:Info('Exclude: '.string(s:exclude))
    call s:Info('Search Exclude: '.string(s:search_exclude))
    call s:Info('Find in files Exclude: '.string(s:find_in_files_exclude))
  else
    call s:Warn('No project opened')
  endif
endfunction

function! project#ShowProjectAllInfo()
  if !empty(s:project)
    call project#ShowProjectInfo()
    call s:Info('------------ Details ------------')
    call s:ShowProjectConfig()
  else
    call s:Warn('No project opened')
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

function! s:SkipStartBuffer()
  if s:reloading_project || s:loading_on_vim_enter
    return 1
  endif

  return 0
endfunction

function! s:InitStartBuffer()
  if s:SkipStartBuffer()
    return
  endif
  call s:OpenNewBufferOnly()
endfunction

function! s:SetStartBuffer()
  if s:SkipStartBuffer()
    return
  endif

  let path = s:GetProjectRootPath()
  if s:ShouldOpenRoot()
    call s:OpenRoot(path)
  else
    call s:ChangeDirectoryToRoot(path)
  endif
endfunction

function! s:ChangeDirectoryToRoot(path)
  execute 'cd '.a:path
endfunction

function! s:DeleteNerdtreeBuf()
  let bufname = expand('%')
  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1
  if is_nerdtree_tmp
    silent bdelete
  endif

  call s:Debug('Opened root from buffer '.bufname)
endfunction

function! s:OpenNewBufferOnly()
  if &buftype == 'terminal'
    " Abandon terminal buffer
    enew!
  else
    if &modified
      " Leave it to uers if it's a modified normal buffer
      new
    else
      enew
    endif
  endif
  silent only
endfunction

function! s:EditPathAsFile(path)
    execute 'edit '.a:path
endfunction

function! s:OpenRootPath(path)
  if exists('g:loaded_nerd_tree')
    let edit_cmd = 'NERDTree'
  else
    let edit_cmd = 'edit'
  endif
  execute edit_cmd.' '.a:path

  silent only
  execute 'cd '.a:path
endfunction

function! s:OpenRoot(path)
  call s:DeleteNerdtreeBuf()

  if empty(a:path)
    call s:OpenNewBufferOnly()
    return
  endif

  if !isdirectory(a:path)
    call s:EditPathAsFile(a:path)
    return
  endif

  call s:OpenRootPath(a:path)
endfunction

function! s:ShouldOpenRoot()
  let bufname = expand('%')
  let is_nerdtree_tmp = count(bufname, s:nerdtree_tmp) == 1

  return s:open_root_when_use_session
        \|| &buftype == 'nofile'
        \|| bufname == ''
        \|| is_nerdtree_tmp
endfunction

function! s:GetProjectRootPath()
  let path = s:project.fullpath
  " Remove the relative part './'
  let root = substitute(s:project_root, '^\.\?[/\\]', '', '')
  let path = path.'/'.root
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
  call s:MapFile()
endfunction

function! s:ResetConfig()
  let g:vim_project_local_config = {}
endfunction

function! s:ReadLocalConfig()
  let local_config = s:GetConfig('local_config', {})
  if !empty(local_config)
    for key in s:local_config_keys
      if has_key(local_config, key)
        if type(local_config[key]) == v:t_list
          let s:[key] = extend(copy(s:[key]), local_config[key])
          continue
        endif

        let s:[key] = local_config[key]
      endif
    endfor
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
    call s:Debug('File not found: '.file)
  endif
endfunction

function! s:FindBranch()
  if !s:check_branch_when_use_session || !s:use_session
    let s:branch = s:branch_default
    return
  endif

  let head_file = s:project.fullpath.'/.git/HEAD'
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
  let should_watch = s:check_branch_when_use_session
        \&& s:use_session
        \&& executable('tail') == 1
        \&& (exists('*job_start') || exists('*jobstart'))

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
        \ { 'callback': 'VimProjectReloadSession' })
endfunction

function! s:WatchHeadFileNeoVim(cmd)
  if s:head_file_job
    call jobstop(s:head_file_job)
  endif
  let s:head_file_job = jobstart(a:cmd,
        \ { 'on_stdout': 'VimProjectReloadSession' })
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

function! VimProjectReloadSession(channel, msg, ...)
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
    call s:Info('Changed branch to '.new_branch)
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

function! s:MapFile()
  let config = s:file_mappings

  for [key, V] in items(config)
    let value_type = type(V)
    if value_type == v:t_string
      call s:MapDirectFile(key, V)
    endif

    if value_type == v:t_list
      call s:MapLinkedFile(key, V)
    endif

    if value_type == v:t_func
      call s:MapCustomFile(key)
    endif
  endfor
endfunction

function! s:MapDirectFile(key, file)
  for [open_key, open_type] in items(s:open_types)
    execute "nnoremap '".open_key.a:key.' :update<cr>'
          \.':call <SID>OpenFile("'.open_type.'", "'.a:file.'")<cr>'
  endfor
endfunction

function! s:MapLinkedFile(key, files)
  for [open_key, open_type] in items(s:open_types)
    execute "nnoremap '".open_key.a:key
          \.' :update<cr>:call <SID>GotoLinkedFile('
          \.s:ListToString(a:files).', '.'"'.open_type.'")<cr>'
  endfor
endfunction

function! s:ListToString(list)
  return '['.join(map(copy(a:list), {nr, val -> '"'.val.'"'}),',').']'
endfunction

function! s:CallCustomFunc(key)
  let Func = s:file_mappings[a:key]
  let target = Func()
  return target
endfunction

function! s:MapCustomFile(key)
  let sid = expand('<SID>')
  for [open_key, open_type] in items(s:open_types)
    execute "nnoremap '".open_key.a:key
          \.' :update<cr>'
          \.' :call <SID>OpenFile("'.open_type.'", <SID>CallCustomFunc("'.a:key.'"))<cr>'
  endfor
endfunction

function! s:GotoLinkedFile(files, open_type)
  if a:files[0] =~ '^\w*$' " By file extension
    let current_index = index(a:files, expand('%:e'))
    if current_index == -1 
      call s:Warn('File map extension not found: '.expand('%:e').' in '.join(a:files, ', '))
    else
      let target =  expand('%:p:r').'.'.a:files[1 - current_index]
    endif
  else " By file name, default to first one
    let current_file = substitute(expand('%:p'), $vim_project.'/', '', '')
    let current_index = index(a:files, current_file)
    if current_index == -1
      let target = a:files[0]
    else
      let target = a:files[1 - current_index]
    endif
  endif

  if exists('target')
    call s:OpenFile(a:open_type, target)
  endif
endfunction

function! s:OpenFile(open_type, target)
  let open_target = a:target
  if s:IsRelativePath(open_target)
    let open_target = $vim_project.'/'.open_target
  endif
  let expended_open_target = expand(open_target)

  if !filereadable(expended_open_target) && !isdirectory(expended_open_target)
    let display_target = s:ReplaceHomeWithTide(s:RemoveProjectPath(expended_open_target))
    call s:Warn('File or folder not found: '.display_target)
    return
  endif

  execute a:open_type.' '.expended_open_target
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
  execute 'silent! 1match FirstColumn /'.s:first_column_pattern.'/'
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
  " The start position of match
  let start = 0

  let first_col_str = matchstr(getline(a:lnum), s:first_column_pattern)
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
    let second_col_str = matchstr(getline(a:lnum), s:second_column_pattern)
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
