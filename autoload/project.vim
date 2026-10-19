if exists('g:vim_project_loaded') | finish | endif

function! s:Prepare()
  let s:name = 'vim-project'
  let s:head_file_job = 0
  let s:file_mapping_keys = []
  let s:project = {}
  let s:branch = ''
  let s:branch_default = ''
  let s:reloading_project = 0
  let s:loading_on_vim_enter = 0
  let s:start_project = {}
  let s:start_buf = ''
  let s:is_init_adding = 0
  let s:nerdtree_tmp = 'vim_project_nerdtree_tmp'
  let s:is_win_version = has('win32') || has('win64')
  let s:note_prefix = '- '

  let s:project_history = []
  let s:add_file = 'project.add.vim'
  let s:ignore_file = 'project.ignore.vim'
  let s:history_file = 'project.history.txt'
  let s:init_file = 'init.vim'
  let s:quit_file = 'quit.vim'

  " Used by statusline
  let g:vim_project = {}

  let s:projects = []
  let s:projects_error = []
  let s:projects_ignore = []
endfunction

function! s:InitConfig()
  call project#config#Init()
  let s:config_home = expand(project#config#Get('config_home'))
endfunction

function! s:GetAddArgs(args)
  if match(a:args, ',\s*\ze{') != -1
    return s:GetAddArgsLegacy(a:args)
  endif

  return s:GetAddArgsNew(a:args)
endfunction

function! s:GetAddArgsLegacy(args)
  let args = split(a:args, ',\s*\ze{')
  let path = args[0]
  let option = len(args) > 1 ? json_decode(args[1]) : {}
  return [path, option]
endfunction

function! s:GetAddArgsNew(args)
  let args = split(a:args, ' *\("\|''\)')
  let path = args[0]
  let note = len(args) > 1 ? args[1] : ''
  let option = { 'note': note }
  return [path, option]
endfunction

function! project#AddProject(args)
  let [path, option] = s:GetAddArgs(a:args)
  let [error, project] = s:AddProject(path, option)
  if error || s:is_init_adding
    return 1
  endif

  let save_path = project#ReplaceHomeWithTide(s:GetFullPath(path))
  if !empty(option)
    let note = get(option, 'note')
    if !empty(note)
      call s:SaveToAddFile(save_path.' "'.note.'"')
    else
      call s:SaveToAddFile(save_path)
    endif
  else
    call s:SaveToAddFile(save_path)
  endif
  redraw
  let message = 'Added ['.path.']'
        \.'. Config at ('.project#ReplaceHomeWithTide(s:config_home).')'
  call s:Info(message)
  call project#OpenProject(project)
endfunction

function! s:AddProject(path, ...)
  let fullpath = s:GetFullPath(a:path)
  let option = a:0 > 0 ? a:1 : {}

  let hasProject = project#ProjectExistWithSameFullPath(
        \fullpath,
        \s:projects
        \)
  if hasProject
    if !s:is_init_adding
      call s:Info('Already has ['.a:path.']')
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
    let created = 0
    if !s:is_init_adding
      let shortpath = project#ReplaceHomeWithTide(fullpath)
      call project#Warn('Directory not found: '.shortpath)

      if project#config#Get('ask_create_directory') == 'yes' && exists("*mkdir")
        let created = s:CreateDirectoryForNewProject(fullpath, shortpath)
      endif
    endif


    if !created
      call insert(s:projects_error, project)
      return [1, v:null]
    endif
  endif

  call s:InitProjectConfig(project)
  call add(s:projects, project)
  return [0, project]
endfunction

function! s:CreateDirectoryForNewProject(fullpath, shortpath)
  echo '[vim-project] Do you want to create directory '.a:shortpath.'? (y/n) '
  if nr2char(getchar()) == 'y'
    redraw
    call mkdir(a:fullpath, 'p')
    call project#Info("Directory created: ".a:shortpath)
    return 1
  endif
  return 0
endfunction

function! project#ProjectExistWithSameFullPath(fullpath, projects)
  let result = 0
  for project in a:projects
    if project.fullpath == a:fullpath
      let result = 1
    endif
  endfor
  return result
endfunction

function! project#IgnoreProject(path)
  let path = project#ReplaceHomeWithTide(a:path)
  let error = s:IgnoreProject(path)
  if !error && !s:is_init_adding
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

function! project#ReplaceHomeWithTide(path)
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
  let hasProject = project#ProjectExistWithSameFullPath(
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

function! s:RemoveTrailSlash(path)
  return substitute(a:path, '[\/\\]$', '', '')
endfunction

function! s:GetFullPath(path)
  let path = a:path
  let path = s:RemoveTrailSlash(path)
  let path = s:GetAbsolutePath(path)
  let path = substitute(expand(path), '\', '\/', 'g')
  call s:Debug('The full path is '.path)
  return path
endfunction

function! project#IsRelativePath(path)
  return s:IsRelativePath(a:path)
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
      let full_path = s:RemoveTrailSlash(expand(fnamemodify(base.'/'.path, ':p')))
      if isdirectory(full_path)
        return full_path
      endif
    endfor
  endif

  if s:IsRelativePath(path)
    let full_path = s:RemoveTrailSlash(expand(fnamemodify(getcwd().'/'.path, ':p')))
    return full_path
  endif
  return path
endfunction

function! s:GetProjectBase()
  return insert(copy(project#config#Get('project_base')), getcwd())
endfunction

function! s:InitProjectConfig(project)
  let name = a:project.name
  let config = project#GetProjectConfigPath(s:config_home, a:project)

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
          \'" Local config. Those of list or dict types extend global config. Others override',
          \'" let g:vim_project_local_config = {',
          \'"   \''include'': [],',
          \'"   \''exclude'': [''.git'', ''node_modules'', ''.DS_Store'', ''.github'', ''.next''],',
          \'"   \''tasks'': [',
          \'"     \{',
          \'"       \''name'': ''start'',',
          \'"       \''cmd'': ''npm start''',
          \'"     \},',
          \'"   \],',
          \'"   \''project_root'': ''./'',',
          \'"   \''use_session'': 0,',
          \'"   \''use_viminfo'': 0,',
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
          \'   \''include'': [''./''],',
          \'   \''exclude'': [''.git'', ''node_modules'', ''.DS_Store'', ''.github'', ''.next''],',
          \'   \''tasks'': [',
          \'     \{',
          \'       \''name'': '''',',
          \'       \''cmd'': ''''',
          \'     \},',
          \'   \],',
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
  if project#config#Get('debug')
    echom '['.s:name.'] '.a:msg
  endif
endfunction

function! s:Info(msg, ...)
  echom '['.s:name.'] '.a:msg
endfunction

function! project#Info(msg, ...)
  echom '['.s:name.'] '.a:msg
endfunction

function! project#InfoEcho(msg)
  echo '['.s:name.'] '.a:msg
endfunction

function! s:InfoHl(msg)
  echohl Type | echom '['.s:name.'] '.a:msg | echohl None
endfunction

function! project#Warn(msg)
  redraw
  echohl WarningMsg
  echom '['.s:name.'] '.a:msg
  echohl None
endfunction

function! project#GetProjectConfigPath(config_home, project)
  let id = a:project.path
  let id = project#ReplaceHomeWithTide(id)
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
  let tail = s:GetPathTail(a:path)
  if s:IsRelativePath(a:path)
    let base_list = s:GetProjectBase()
    let head = join(map(base_list, {_, val -> fnamemodify(val.'/'.head, ':p')}), ',')
  endif

  let dirs = split(globpath(head, '*'), "\n")
  call map(dirs,
        \{_, val -> s:ReplaceBackSlash(val)})

  call filter(dirs,
        \{_, val -> match(s:GetPathTail(val), tail) != -1})
  call filter(dirs,
        \{_, val -> isdirectory(expand(val))})
  call map(dirs,
        \{_, val -> project#ReplaceHomeWithTide(val)})

  " If only one found, append a '/' to differentiate it from user input
  if len(dirs) == 1 && isdirectory(expand(dirs[0]))
    let dirs[0] = dirs[0].'/'
  endif

  return dirs
endfunction

function! s:GetPathHead(path)
  return matchstr(a:path, '.*/\ze[^/]*$')
endfunction

function! s:GetPathTail(path)
  let tail = matchstr(a:path, '^[^/]*$')
  if empty(tail)
    let tail = matchstr(a:path, '.*/\zs[^/]*$')
  endif
  return tail
endfunction

" Call this entry function first
function! project#Begin()
  let g:vim_project_loaded = 1
  call s:Main()
  call s:SourcePluginConfigFiles()
  call s:ReadProjectHistory()
  call s:WatchOnBufEnter()
endfunction

function! project#CheckVersion()
  return s:CheckVersion()
endfunction

function! s:CheckVersion()
  if exists('g:vim_project_config')
        \&& type(g:vim_project_config) == type('')
    let message1 = 'Hey, it seems that you just upgraded. Please configure `g:vim_project_config` as a dict'
    let message2 = 'For details, please check README.md or https://github.com/leafOfTree/vim-project'
    echom '[vim-project] '.message1
    echom '[vim-project] '.message2
    return 1
  endif

  return 0
endfunction

function! s:ReadProjectHistory()
  let history_file = s:config_home.'/'.s:history_file
  if filereadable(history_file)
    let s:project_history = readfile(history_file)
  endif
endfunction

function! s:SourcePluginConfigFiles()
  let add_file = s:config_home.'/'.s:add_file
  let ignore_file = s:config_home.'/'.s:ignore_file
  let s:is_init_adding = 1
  if filereadable(add_file)
    execute 'source '.add_file
  endif
  if filereadable(ignore_file)
    execute 'source '.ignore_file
  endif
  let s:is_init_adding = 0
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

  let target = project#ReplaceHomeWithTide(a:path)
  let target_pat = '\s'.escape(target, '~\/').'\ze\($\|\/\|,\)'
  let idx = 0
  for line in adds
    if project#Include(line, target_pat)
      let adds[idx] = substitute(line, target_pat, ' '.a:new_fullpath, '')
    endif
    let idx += 1
  endfor
  call writefile(adds, file)
endfunction

function! s:GetItemIndexInProjectAddConfig(adds, path)
  let target = project#ReplaceHomeWithTide(a:path)
  let target_pat = '\s'.escape(target, '~\/').',\?'
  let idx = 0
  for line in a:adds
    if project#Include(line, target_pat)
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
    if project#config#Get('auto_load_on_start')
      " The event order is BufEnter then VimEnter
      autocmd BufEnter * ++once call s:SetStartProjectOnBufEnter()
      autocmd VimEnter * ++once call s:AutoloadOnVimEnter()
    endif
    if project#config#Get('auto_detect') != 'no'
      autocmd BufEnter * call s:AutoDetectProject()
    endif
  augroup END
endfunction

function! s:WatchOnInitFileChange()
  augroup vim-project-init-file-change
    autocmd! vim-project-init-file-change
    autocmd BufWritePost $vim_project_config/init.vim call s:OnInitFileChange()
    
  augroup END
endfunction

function! s:UnwatchOnInitFileChange()
  autocmd! vim-project-init-file-change
endfunction

function! s:OnInitFileChange()
  redraw
  call s:Info('Config Reloaded')
  call s:SourceInitFile()
  call project#search_files#Reset()
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

function! s:DoBufEventOnVimEnter()
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
  call s:DoBufEventOnVimEnter()
endfunction

function! s:AutoDetectProject()
  if &buftype == ''
    let buf = expand('<amatch>')
    let path = s:GetPathContain(buf, project#config#Get('auto_detect_file'))
    if !empty(path)
      let project = s:GetProjectByFullpath(s:projects, path)
      let ignore = s:GetProjectByFullpath(s:projects_ignore, path)

      if empty(project) && empty(ignore)
        let path = project#ReplaceHomeWithTide(path)
        if project#config#Get('auto_detect') == 'always'
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
  call filter(projects, {_, project -> project#Include(a:path, project.fullpath)})
  if len(projects) == 1
    return projects[0]
  endif
  if len(projects) > 1
    call sort(projects, {i1, i2 -> len(i2.fullpath) - len(i1.fullpath)})
    return projects[0]
  endif

  return {}
endfunction


function! s:WatchOnVimQuit()
  augroup vim-quit
    autocmd! vim-quit
    autocmd VimLeave * call s:QuitProject()
    autocmd VimLeave * call s:SaveProjectHistory()
  augroup END
endfunction

function! project#RunShellCmd(cmd, ...)
  let warning = get(a:000, 0, 1)
  let cd_option = s:is_win_version ? '/d' : ''
  let cmd = 'cd '.cd_option.' '.shellescape($vim_project).' && '.a:cmd
  try
    let output = systemlist(cmd)
  catch
    call project#Warn('Exception on running '.a:cmd)
    call project#Warn(v:exception)
    return []
  endtry

  if v:shell_error
    if !empty(output) && warning
      call project#Warn('----------------------------------------')
      call project#Warn(a:cmd)
      for error in output
        let formatted_error = substitute(error, '	', '    ', 'g')
        call project#Warn(formatted_error)
      endfor
      redraw
      execute (len(output) + 2).'messages'
    endif
    return []
  endif

  return output
endfunction

function! project#HasMoreOnList(list)
  return len(a:list) && has_key(a:list[0], 'more') && a:list[0].more
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
    call project#OpenProject(project)
  else
    call project#Warn('Project not found: ['.a:name.']')
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
    call project#Warn('Project not found: ['.a:name.']')
  endif
endfunction

function! s:RenameProjectByName(name, new_name)
  let project = s:GetProjectByName(a:name, s:projects)
  if empty(project)
    let project = s:GetProjectByName(a:name, s:projects_error)
  endif

  if empty(project)
    call project#Warn('Project not found: ['.a:name.']')
  else
    call s:RenameProject(project, a:new_name)

    let s:projects = []
    let s:projects_error = []
    call s:SourcePluginConfigFiles()
  endif
endfunction

function! project#RemoveProjectByName(name)
  call s:RemoveProjectByName(a:name, 0)
endfunction

function! project#RenameProjectByName(args)
  let names = s:ParseRenameArgs(a:args)
  if len(names) != 2 || empty(names[1])
    call project#Warn('Usage: ProjectRename <name> <new_name>. '
          \.'Quote or escape names with spaces, e.g. "my project" new-name')
    return
  endif
  call s:RenameProjectByName(names[0], names[1])
endfunction

" Split ':ProjectRename' args into [name, new_name]. A name may be quoted
" ("a b" or 'a b') or have escaped spaces (a\ b). An unquoted name may
" also contain plain spaces when it is an existing project name, as
" inserted by completion.
function! s:ParseRenameArgs(args)
  let args = trim(a:args)
  if args =~ '^["'']' || args =~ '\\ '
    return s:SplitQuotedArgs(args)
  endif

  " Longest existing name followed by a space
  let names = map(copy(s:projects + s:projects_error), {_, project -> project.name})
  call sort(names, {a, b -> len(b) - len(a)})
  for name in names
    if stridx(args, name.' ') == 0
      return [name, trim(args[len(name):])]
    endif
  endfor

  return s:SplitQuotedArgs(args)
endfunction

" Split on spaces outside quotes, honoring backslash-escaped spaces
function! s:SplitQuotedArgs(args)
  let result = []
  let rest = a:args
  let token_pattern = '^\s*\%("\([^"]*\)"\|''\([^'']*\)''\|\(\%(\\.\|\S\)\+\)\)\(.*\)$'
  while rest !~ '^\s*$'
    let parts = matchlist(rest, token_pattern)
    if empty(parts)
      break
    endif
    if !empty(parts[1]) || rest =~ '^\s*""'
      call add(result, parts[1])
    elseif !empty(parts[2]) || rest =~ "^\\s*''"
      call add(result, parts[2])
    else
      call add(result, substitute(parts[3], '\\\(.\)', '\1', 'g'))
    endif
    let rest = parts[4]
  endwhile
  return result
endfunction

function! project#ReloadProject()
  call s:ReloadProject()
endfunction

function! s:ReloadProject()
  if project#ProjectExist()
    call s:SaveAllBuffers()
    let s:reloading_project = 1

    let project = s:project
    call s:QuitProject()
    call project#OpenProject(project)

    redraw
    call s:Info('Reloaded')
    let s:reloading_project = 0
  endif
endfunction

function! s:SaveAllBuffers()
  wa
endfunction

function! project#OpenProject(project)
  if s:project != a:project
    call s:ClearCurrentProject()
    let s:project = a:project

    call s:PreLoadProject()
    call s:LoadProject()
    call s:PostLoadProject()
    call s:AddProjectHistory(s:project)
    redraw
    call s:Info('Opened ['.a:project.name.']')
  else
    call s:Info('Already opened')
  endif
endfunction

function! s:AddProjectHistory(project)
  let item = a:project.fullpath
  let idx = index(s:project_history, item)
  if idx != -1
    call remove(s:project_history, idx)
  endif

  call insert(s:project_history, item)
endfunction

function! s:SaveProjectHistory()
  let file = s:config_home.'/'.s:history_file
  call writefile(s:project_history, file)
endfunction

function! s:PreLoadProject()
  call s:InitStartBuffer()
  call s:SetEnvVariables()
endfunction

function! s:LoadProject()
  call s:SourceInitFile()
  call s:WatchOnInitFileChange()
  call s:FindBranch()
  call s:LoadViminfo()
  call s:LoadSession()
endfunction

function! s:PostLoadProject()
  call s:SetStartBuffer()
  call s:SyncGlobalVariables()
  call s:StartWatchJob()
  call s:WatchOnVimQuit()
endfunction

function! s:ClearCurrentProject()
  if project#ProjectExist()
    call s:QuitProject()
    silent! %bdelete!
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
    call s:Info('Removed the record of ['. a:project.name.'] from ('.a:project.path.')')
    call s:SaveToPluginConfigIgnore(a:project.fullpath)
    call s:RemoveItemInProjectAddConfig(a:project.fullpath)
  endif
endfunction

function! s:RenameProject(project, new_name)
  if a:project == s:project
    call s:QuitProject()
  endif

  let new_fullpath = a:project.path.'/'.a:new_name
  if isdirectory(new_fullpath)
    call project#Warn(new_fullpath.' already exists')
    return
  endif

  call s:Info('Renamed '.a:project.name.' to '.a:new_name.' ('.a:project.path.')')
  call rename(a:project.fullpath, new_fullpath)
  call s:RenamePathInProjectAddConfig(a:project.fullpath, project#ReplaceHomeWithTide(new_fullpath))

  let config_path = project#GetProjectConfigPath(s:config_home, a:project)
  let a:project.name = a:new_name
  let new_config_path = project#GetProjectConfigPath(s:config_home, a:project)
  call rename(config_path, new_config_path)
endfunction

function! s:SetEnvVariables()
  let $vim_project = s:project.fullpath
  let $vim_project_config =
        \project#GetProjectConfigPath(s:config_home, s:project)
endfunction

function! s:UnsetEnvVariables()
  unlet $vim_project
  unlet $vim_project_config
endfunction

function! project#ProjectExist()
  if empty(s:project)
    return 0
  else
    return 1
  endif
endfunction

" The project currently open, or {}
function! project#GetCurrentProject()
  return s:project
endfunction

function! project#GetProjects()
  return s:projects
endfunction

" Full paths of opened projects, most recent first
function! project#GetProjectHistory()
  return s:project_history
endfunction

function! project#OpenProjectRoot()
  if project#ProjectExist()
    let path = s:GetProjectRootPath()
    if !empty(path)
      execute 'edit '.path
    endif
  endif
endfunction

function! project#OpenProjectConfig()
  if !project#util#RequireProject()
    return
  endif

  let config = project#GetProjectConfigPath(s:config_home, s:project)
  execute 'tabedit '.config.'/'.s:init_file
endfunction

function! project#OpenAllConfig()
  execute 'tabedit '.s:config_home.'/project.add.vim'
endfunction

function! project#QuitProject()
  call s:QuitProject()
endfunction

function! s:QuitProject()
  if project#ProjectExist()
    call s:Info('Quitted ['.s:project.name.']')
    call s:SaveViminfo()
    call s:SaveSession()
    call s:SourceQuitFile()
    call s:UnwatchOnInitFileChange()
    call s:UnmapFile()
    call s:StopWatchJob()

    call project#list#ClearHistory()
    let s:project = {}
    call s:UnsetEnvVariables()
    call project#list#Wipeout()
    call project#run_tasks#WipeoutTerminalBuffer()
    call project#search_files#Reset()
    call project#run_tasks#Reset()

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
  if !project#util#RequireProject()
    return
  endif

  call s:Info('Name: '.s:project.name)
  call s:Info('Path: '.project#ReplaceHomeWithTide(s:project.path))
  call s:Info('config_home: '.project#config#Get('config_home'))
  call s:Info('project_base: '.join(project#config#Get('project_base'), ', '))
  call s:Info('Include: '.string(project#config#Get('include')))
  call s:Info('Exclude: '.string(project#config#Get('exclude')))
  call s:Info('Search Include: '.string(project#config#Get('search_include')))
  call s:Info('Search Exclude: '.string(project#config#Get('search_exclude')))
  call s:Info('Find in files Include: '.string(project#config#Get('find_in_files_include')))
  call s:Info('Find in files Exclude: '.string(project#config#Get('find_in_files_exclude')))
endfunction

function! project#ShowProjectAllInfo()
  if !project#util#RequireProject()
    return
  endif

  call project#ShowProjectInfo()
  call s:Info('------------ Details ------------')
  call s:ShowProjectConfig()
endfunction

function! s:ShowProjectConfig()
  let config = project#config#All()
  for key in sort(keys(config))
    call s:Info(key.': '.string(config[key]))
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

  return project#config#Get('open_root_when_use_session')
        \|| &buftype == 'nofile'
        \|| bufname == ''
        \|| is_nerdtree_tmp
endfunction

function! s:GetProjectRootPath()
  let path = s:project.fullpath
  " Remove the relative part './'
  let root = substitute(project#config#Get('project_root'), '^\.\?[/\\]', '', '')
  let path = path.'/'.root
  if isdirectory(path) || filereadable(path)
    return path
  else
    redraw
    call project#Warn('Project path not found: '.path)
    return ''
  endif
endfunction

function! s:SourceInitFile()
  call project#config#ResetLocal()
  call s:InitConfig()
  call s:SourceFile(s:init_file)
  call project#config#ReadLocal()
  call project#config#Adjust()
  call s:MapFile()
endfunction

function! s:SourceQuitFile()
  call s:SourceFile(s:quit_file)
endfunction

function! s:SourceFile(file)
  let name = s:project.name.'-'.s:project.path
  let config = project#GetProjectConfigPath(s:config_home, s:project)
  let file = config.'/'.a:file
  if filereadable(file)
    call s:Debug('Source file: '.file)
    execute 'source '.file
  else
    call s:Debug('File not found: '.file)
  endif
endfunction

function! s:FindBranch()
  if !project#config#Get('check_branch_when_use_session') || !project#config#Get('use_session')
    let s:branch = s:branch_default
    return
  endif

  let head_file = s:project.fullpath.'/.git/HEAD'
  if filereadable(head_file)
    let head = join(readfile(head_file), "\n")
    let s:branch = matchstr(head, 'refs\/heads\/\zs.*')
    call s:Debug('Find branch: '.s:branch)
  else
    call s:Info('Not a git repository')
    let s:branch = s:branch_default
  endif
endfunction

function! s:GetSessionFolder()
  let config = project#GetProjectConfigPath(s:config_home, s:project)
  return config.'/sessions'
endfunction

function! s:GetSessionFile()
  let config = project#GetProjectConfigPath(s:config_home, s:project)
  return config.'/sessions/'.s:branch.'.vim'
endfunction

function! s:LoadViminfo()
  if !project#config#Get('use_viminfo')
    return
  endif

  let file = s:GetViminfoFile()
  if filereadable(file)
    call s:Debug('Load viminfo file: '.file)
    if has('nvim')
      execute 'rshada! '.file
    else
      execute 'rviminfo! '.file
    endif
  endif
endfunction

function! s:SaveViminfo()
  if !project#config#Get('use_viminfo')
    return
  endif

  let folder = s:GetViminfoFolder()
  if !isdirectory(folder) && exists('*mkdir')
    call mkdir(folder, 'p')
  endif

  let file = s:GetViminfoFile()
  call s:Debug('Save viminfo to: '.file)
  if has('nvim')
    execute 'wshada! '.file
  else
    execute 'wviminfo! '.file
  endif
endfunction

function! s:GetViminfoFile()
  let config = project#GetProjectConfigPath(s:config_home, s:project)
  if has('nvim')
    return config.'/viminfo/main.shada'
  else
    return config.'/viminfo/.viminfo'
  endif
endfunction

function! s:GetViminfoFolder()
  let config = project#GetProjectConfigPath(s:config_home, s:project)
  return config.'/viminfo'
endfunction

function! s:LoadSession()
  if !project#config#Get('use_session')
    return
  endif

  let file = s:GetSessionFile()
  if filereadable(file)
    call s:Debug('Load session file: '.file)
    execute 'source '.file
  else
    call s:Debug('No session file found: '.file)
  endif
endfunction

function! s:StartWatchJob()
  let should_watch = project#config#Get('check_branch_when_use_session')
        \&& project#config#Get('use_session')
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
  call s:StopWatchJob()
  let s:head_file_job = job_start(a:cmd,
        \ { 'callback': function('s:ReloadSessionOnBranchChange') })
endfunction

function! s:WatchHeadFileNeoVim(cmd)
  call s:StopWatchJob()
  let s:head_file_job = jobstart(a:cmd,
        \ { 'on_stdout': function('s:ReloadSessionOnBranchChange') })
endfunction

function! s:StopWatchJob()
  if exists('*job_stop') && type(s:head_file_job) == v:t_job
    call job_stop(s:head_file_job)
  elseif exists('*jobstop') && type(s:head_file_job) == v:t_number && s:head_file_job > 0
    silent! call jobstop(s:head_file_job)
  endif
  let s:head_file_job = 0
endfunction

function! s:SaveSession()
  if !project#config#Get('use_session')
    return
  endif

  if project#ProjectExist()
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

" Job callback: vim passes (channel, msg), nvim passes (job, data, event)
function! s:ReloadSessionOnBranchChange(channel, msg, ...)
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

function! s:MapFile()
  call s:UnmapFile()
  let config = project#config#Get('file_mappings')

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
  for [open_key, open_type] in items(project#config#Get('file_open_types'))
    call s:AddFileMapping(open_key.a:key,
          \':call <SID>OpenFile("'.open_type.'", "'.a:file.'")<cr>')
  endfor
endfunction

function! s:MapLinkedFile(key, files)
  for [open_key, open_type] in items(project#config#Get('file_open_types'))
    call s:AddFileMapping(open_key.a:key,
          \':call <SID>GotoLinkedFile('.s:ListToString(a:files).', "'.open_type.'")<cr>')
  endfor
endfunction

" The default prefix "'" shadows jumping to marks while a project is open;
" file_mappings_prefix can move the mappings elsewhere, e.g. '<leader>'
function! s:AddFileMapping(key, rhs)
  let prefix = project#config#Get('file_mappings_prefix')
  let lhs = (empty(prefix) ? "'" : prefix).a:key
  execute 'nnoremap '.lhs.' :update<cr>'.a:rhs
  call add(s:file_mapping_keys, lhs)
endfunction

" Remove mappings added by s:MapFile so they do not leak into other projects
function! s:UnmapFile()
  for lhs in s:file_mapping_keys
    silent! execute 'nunmap '.lhs
  endfor
  let s:file_mapping_keys = []
endfunction

function! s:ListToString(list)
  return '['.join(map(copy(a:list), {nr, val -> '"'.val.'"'}),',').']'
endfunction

function! s:CallCustomFunc(key)
  let Func = project#config#Get('file_mappings')[a:key]
  let target = Func()
  return target
endfunction

function! s:MapCustomFile(key)
  for [open_key, open_type] in items(project#config#Get('file_open_types'))
    call s:AddFileMapping(open_key.a:key,
          \':call <SID>OpenFile("'.open_type.'", <SID>CallCustomFunc("'.a:key.'"))<cr>')
  endfor
endfunction

function! s:GotoLinkedFile(files, open_type)
  if a:files[0] =~ '^\w*$' " By file extension
    let current_index = index(a:files, expand('%:e'))
    if current_index == -1 
      call project#Warn('File map extension not found: '.expand('%:e').' in '.join(a:files, ', '))
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
    let display_target = project#ReplaceHomeWithTide(
          \s:RemoveProjectPath(expended_open_target))
    call project#Warn('File or folder not found: '.display_target)
    return
  endif

  execute a:open_type.' '.expended_open_target
endfunction

function! project#Include(string, search_string)
  return match(a:string, a:search_string) != -1
endfunction

function! project#GetProjectDirectory()
  let path = $vim_project.'/'
  if !has('nvim')
    let path = project#ReplaceHomeWithTide(path)
  endif
  return path
endfunction

function! project#SetOsSlash(val)
  if s:is_win_version
    return substitute(a:val, '/', '\', 'g')
  else
    return substitute(a:val, '\', '/', 'g')
  endif
endfunction

function! project#ShortenDate(origin)
  let date = substitute(a:origin, ' years\?', 'y', 'g')
  let date = substitute(date, ' months\?', 'mon', 'g')
  let date = substitute(date, ' weeks\?', 'w', 'g')
  let date = substitute(date, ' days\?', 'd', 'g')
  let date = substitute(date, ' hours\?', 'h', 'g')
  let date = substitute(date, ' minutes\?', 'min', 'g')
  return date
endfunction

" Strip carriage returns, as from CRLF files or git on Windows
function! project#RemoveEmptyLines()
  silent! %s/\r$//ge
endfunction

try
  call nerdfont#find('')
  function! project#GetIcon(fullpath)
    let icon = nerdfont#find(a:fullpath, isdirectory(a:fullpath) ? 'close' : 0)
    if empty(icon)
      return ''
    else
      return icon.' '
    endif
  endfunction
catch 
  function! project#GetIcon(fullpath)
    return ''
  endfunction
endtry

try 
  call glyph_palette#clear()
  function! project#HighlightIcon()
    call glyph_palette#apply()
  endfunction
catch
  function! project#HighlightIcon()
  endfunction
endtry

function! s:Main()
  call s:Prepare()
  call s:InitConfig()
  call project#config#Adjust()
endfunction
