let s:search_files_sort_max = 1000
let s:prev_list = []
let s:prev_display = []
let s:prev_input = ''
let s:update_timer = 0
" Background refresh of s:initial_list, see s:StartRefresh()
let s:refresh_job = v:null
let s:refresh_id = 0
" Whether s:initial_list came from fd, which marks directories
let s:initial_list_marks_dirs = 0
let s:refresh_lines = []

function! project#search_files#Run()
  if !project#util#RequireProject()
    return
  endif

  call project#list#Open({
        \'type': 'SEARCH_FILES',
        \'prompt': 'Search files by name:',
        \'mappings': project#config#Get('list_mappings_search_files'),
        \'Init': function('s:Init'),
        \'Update': function('s:UpdateTimer'),
        \'Open': function('s:Open'),
        \})
endfunction

function! project#search_files#Reset()
  call s:StopRefresh()
  unlet! s:initial_list
  call s:ClearResultCache()
endfunction

function! s:ClearResultCache()
  let s:prev_list = []
  let s:prev_display = []
  let s:prev_input = ''
endfunction

function! s:Init(input)
  " The first search lists files synchronously. Later ones show the cached
  " list at once and refresh it in the background, so files added or
  " removed outside Vim show up without :ProjectSearchFilesReset
  let has_cache = exists('s:initial_list')
  call s:Update(a:input)
  if has_cache
    call s:StartRefresh()
  endif
endfunction

function! s:UpdateTimer(input)
  call timer_stop(s:update_timer)
  if s:ShouldRunWithTimer(a:input)
    let s:update_timer = timer_start(100, function('s:Update', [a:input]))
  else
    call s:Update(a:input)
  endif
endfunction

function! s:ShouldRunWithTimer(input)
  return (s:prev_input != a:input) && !empty(a:input)
endfunction

function! s:Update(input, ...)
  " The timer may fire after the list has closed
  if !project#list#IsCurrentListBuffer()
    return
  endif

  let use_cache = a:input == s:prev_input && !empty(s:prev_list)
  if use_cache
    let list = s:prev_list
    let display = s:prev_display
  else
    let [list, display] = s:GetSearchFilesResult(a:input)
    let s:prev_list = list
    let s:prev_display = display
    let s:prev_input = a:input
  endif

  let state = project#list#State()
  let state.input = a:input
  let state.list = list
  call project#list#Show(display, a:input)
  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
  call project#HighlightIcon()
  call project#list#HighlightExtraInfo()
  call project#list#RedrawInputLine()
endfunction

function! s:Open(target, open_cmd, input)
  let cmd = substitute(a:open_cmd, 'open_\?', '', '')
  let cmd = cmd == '' ? 'edit' : cmd
  let file = $vim_project.'/'.a:target.path.'/'.a:target.file
  execute cmd fnameescape(file)
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

function! s:DecorateSearchFilesDisplay(list, display)
  if project#HasMoreOnList(a:list)
    let a:display[0] = substitute(a:display[0], '\s*$', '  ...more', 'g')
  endif

  let recent_index = s:GetRecentIndex(a:list)
  if recent_index != -1
    let a:display[recent_index] .= ''
  endif
endfunction

" columns: the tabulated file and path of each item, see project#list#Tabulate
function! s:GetSearchFilesDisplay(list, columns)
  let display = map(copy(a:list), function('s:GetSearchFilesDisplayRow', [a:columns]))
  call s:DecorateSearchFilesDisplay(a:list, display)
  return display
endfunction

function! s:GetFileFullpath(value)
  return $vim_project.'/'.a:value.path.'/'.a:value.file
endfunction

function! s:GetSearchFilesDisplayRow(columns, idx, value)
  let column = a:columns[a:idx]
  let fullpath = s:GetFileFullpath(a:value)
  if get(a:value, 'dir', 0) || isdirectory(fullpath)
    let file = substitute(column.file, '\S\zs\s\|\S\zs$', '/', '')
  else
    let file = column.file
  endif
  let icon = project#GetIcon(fullpath)
  return icon.file.'  '.column.path
endfunction

function! s:GetSearchFilesByOldFiles(input)
  let oldfiles = s:GetOldFiles()
  call s:FilterOldFilesByPath(oldfiles)
  call s:MapSearchFiles(oldfiles)
  call s:FilterOldFilesByInput(oldfiles, a:input)
  call s:SortSearchFilesList(oldfiles, a:input)
  call s:UseOsSlash(oldfiles)
  return oldfiles
endfunction

function! s:UseOsSlash(oldfiles)
  call map(a:oldfiles, {_, val -> { 'file': val.file, 'path': project#SetOsSlash(val.path)}})
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
    if has('nvim')
      let bufname = buf.name
    else
      let bufname = project#ReplaceHomeWithTide(buf.name)
    endif
    call insert(a:oldfiles, bufname)
  endfor
endfunction

function! s:FilterOldFilesByPath(oldfiles)
  let project_dir = project#GetProjectDirectory()
  call filter(a:oldfiles, {_, val -> count(val, project_dir) > 0 })
  let search_exclude = s:GetExclude()
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
  return a:string[0:len(a:search)-1] ==# a:search && a:string[len(a:search)] == '/'
endfunction

function! s:FilterOldFilesByInput(oldfiles, input)
  let pattern = project#util#FuzzyRegexp(a:input)
  call filter(a:oldfiles,
        \{_, val -> val.file =~ pattern})
endfunction

function! s:GetFindCmd()
  let include = join(s:GetInclude(), ' ')

  let search_exclude = s:GetExclude()
  let exclude_string = join(map(search_exclude, {_, val -> '-name "'.val.'"'}), ' -o ')
  let exclude = '\( '.exclude_string.' \) -prune -false -o '

  let filter = '-ipath "*"'
  return 'find '.include.' -mindepth 1 '.exclude.filter
endfunction

function! s:GetFdCmd()
  let include = join(s:GetInclude(), ' ')

  let search_exclude = s:GetExclude()
  let exclude = join(map(search_exclude, {_, val -> '-E "'.val.'"'}), ' ')

  return 'fd -HI '.exclude.' . '.include
endfunction

function! s:GetFilesByFind()
  return project#RunShellCmd(s:GetFindCmd())
endfunction

function! s:GetFilesByFd()
  return project#RunShellCmd(s:GetFdCmd())
endfunction

function! s:GetFilesByGlob()
  let original_wildignore = &wildignore
  let cwd = getcwd()
  execute 'cd' fnameescape($vim_project)
  for exclue in s:GetExclude()
    execute 'set wildignore+=*/'.exclue.'*'
  endfor

  let result = []
  for path in s:GetInclude()
    let result = result + glob(path.'/**/*', 0, 1)
  endfor

  execute 'cd' fnameescape(cwd)
  let &wildignore = original_wildignore
  return result
endfunction

function! s:GetSearchFilesResultList(input)
  if !exists('s:initial_list')
    let list = s:GetSearchFilesAll()
  else
    let list = s:GetSearchFilesByFilter(s:initial_list, a:input)
  endif
  return list
endfunction

function! s:TrySearchFilesProgram()
  " Try fd, find, glob (vim function) in order
  let find_cmd_map = {
        \'fd': function('s:GetFilesByFd'),
        \'find': function('s:GetFilesByFind'),
        \'glob': function('s:GetFilesByGlob'),
        \}

  let find_program = project#util#PickExecutable(['fd', 'find'], 'glob')
  let s:find_cmd_func = find_cmd_map[find_program]
  let s:find_program = find_program
  return find_program
endfunction

" Shell command listing the files, or '' when glob() is used
function! s:GetListFilesCmd()
  if !exists('s:find_program')
    call s:TrySearchFilesProgram()
  endif
  if s:find_program ==# 'fd'
    return s:GetFdCmd()
  elseif s:find_program ==# 'find'
    return s:GetFindCmd()
  endif
  return ''
endfunction

" ---------------------------------------------------------------- refresh

function! s:CanRefresh()
  return exists('*job_start') || exists('*jobstart')
endfunction

function! s:IsRefreshing()
  if s:refresh_job is v:null
    return 0
  endif
  if exists('*job_status')
    return job_status(s:refresh_job) ==# 'run'
  endif
  return jobwait([s:refresh_job], 0)[0] == -1
endfunction

" List the files again with a job. When done, replace s:initial_list and,
" if the search files list is still open and the files changed, show it
" again with the current input.
function! s:StartRefresh()
  let cmd = s:GetListFilesCmd()
  if empty(cmd) || !s:CanRefresh() || s:IsRefreshing()
    return
  endif

  let s:refresh_id += 1
  let s:refresh_lines = []
  let shell_cmd = [&shell, &shellcmdflag, cmd]
  let Done = function('s:OnRefreshDone', [s:refresh_id, $vim_project])

  if exists('*job_start')
    let s:refresh_job = job_start(shell_cmd, {
          \'cwd': $vim_project,
          \'out_mode': 'nl',
          \'err_io': 'null',
          \'out_cb': {_, line -> add(s:refresh_lines, line)},
          \'exit_cb': {job, status -> s:OnVimRefreshExit(job, status, Done)},
          \})
  else
    let s:refresh_job = jobstart(shell_cmd, {
          \'cwd': $vim_project,
          \'stdout_buffered': v:true,
          \'on_stdout': {_, data, __ -> extend(s:refresh_lines, data)},
          \'on_exit': {_, status, __ -> Done(status)},
          \})
  endif
endfunction

" exit_cb may run before all output was read; wait for the channel
function! s:OnVimRefreshExit(job, status, Done)
  let channel = job_getchannel(a:job)
  let tries = 0
  while ch_status(channel) ==# 'open' && tries < 100
    sleep 5m
    let tries += 1
  endwhile
  call a:Done(a:status)
endfunction

function! s:OnRefreshDone(id, project, status)
  let s:refresh_job = v:null
  " Ignore a refresh superseded by Reset or for another project
  if a:id != s:refresh_id || a:project !=# $vim_project || a:status != 0
    return
  endif

  let lines = filter(s:refresh_lines, {_, line -> !empty(line)})
  let s:refresh_lines = []
  call s:MapSearchFiles(lines)
  let new_list = lines
  if exists('s:initial_list') && new_list == s:initial_list
    return
  endif

  let s:initial_list = new_list
  let s:initial_list_marks_dirs = s:find_program ==# 'fd'
  call s:ClearResultCache()
  if project#list#IsOpen('SEARCH_FILES')
    call s:Update(project#list#State().user_input)
  endif
endfunction

function! s:StopRefresh()
  let s:refresh_id += 1
  if s:IsRefreshing()
    if exists('*job_stop')
      call job_stop(s:refresh_job)
    else
      call jobstop(s:refresh_job)
    endif
  endif
  let s:refresh_job = v:null
  let s:refresh_lines = []
endfunction

function! s:GetSearchFilesAll()
  if !exists('s:find_cmd_func')
    call s:TrySearchFilesProgram()
  endif

  let result = s:find_cmd_func()
  call s:MapSearchFiles(result)
  let s:initial_list = result
  let s:initial_list_marks_dirs = s:find_program ==# 'fd'
  let list = copy(s:initial_list)
  return list
endfunction

function! s:SortByFileThenDirectory(result)
  call sort(a:result, function('s:SortByFileThenDirectoryFunc'))
endfunction

function! s:SortByFileThenDirectoryFunc(item1, item2)
  let is_dir1 = isdirectory($vim_project.'/'.a:item1.path.'/'.a:item1.file)
  let is_dir2 = isdirectory($vim_project.'/'.a:item2.path.'/'.a:item2.file)
  if is_dir1 && !is_dir2
    return 1
  elseif !is_dir1 && is_dir2
    return -1
  endif
  return a:item2.file > a:item1.file ? -1 : 1
endfunction

" Match the name first: it is cheap, while isdirectory() is a file system
" call. fd marks directories, so most items need no call at all
function! s:GetSearchFilesByDirectory(val, filter)
  if a:val.file !~ a:filter
    return 0
  endif
  return has_key(a:val, 'dir') ? a:val.dir : isdirectory(s:GetFileFullpath(a:val))
endfunction

function! s:GetSearchFilesByFilterForDirectory(initial_list, input)
  let list = []
  let filter = substitute(a:input, '/$', '', '')
  let filter_literal = project#util#LiteralRegexp(filter)
  let list = filter(copy(a:initial_list), {_, val -> s:GetSearchFilesByDirectory(val, filter_literal)})

  if len(list) < s:GetMaxHeight()
    call s:SortSearchFilesList(list, filter)

    let filter_fuzzy = project#util#FuzzyRegexp(filter)
    let list_extra = filter(copy(a:initial_list), {_, val -> s:GetSearchFilesByDirectory(val, filter_fuzzy)})
    call s:SortSearchFilesList(list_extra, filter)
    let list += list_extra
  endif

  return list
endfunction

function! s:GetSearchFilesByFilterForAll(initial_list, input, ...)
  let match_fullpath = get(a:000, 0, 0)
  let filter_origin = a:input
  let max_height = s:GetMaxHeight()
  let list = []

  " 1. Prefix match for short input
  if strlen(filter_origin) < 3
    let filter_start = '\V\^'.escape(filter_origin, '\')
    for val in a:initial_list
      if val.file =~ filter_start
        call add(list, val)
      endif
    endfor
  endif

  " 2. Normal substring match for file and directory
  if len(list) < max_height
    let list = []
    for val in a:initial_list
      let match_file_or_path = stridx(val.file, filter_origin) >= 0
            \|| (empty(val.file) && stridx(val.path, filter_origin) >= 0)
      if match_file_or_path
        call add(list, val)
      endif
    endfor
    call s:SortSearchFilesList(list, a:input)
  endif

  " 3. Fuzzy match
  let filter_fuzzy = project#util#FuzzyRegexp(filter_origin)
  if len(list) < 3
    let list_extra = []
    for val in a:initial_list
      if val.file =~ filter_fuzzy
        call add(list_extra, val)
      endif
    endfor
    call s:SortSearchFilesList(list_extra, a:input)
    let list += list_extra
  endif

  if !match_fullpath
    return list
  endif

  " Match fullpath
  if len(list) < s:GetMaxHeight()
    let filter_literal = project#util#LiteralRegexp(filter_origin)
    let list_extra = filter(copy(a:initial_list), {_, val -> val.path.val.file =~ filter_literal})
    let list += list_extra
  endif

  " Fuzzy match fullpath
  if len(list) < s:GetMaxHeight()
    let list_extra = filter(copy(a:initial_list), {_, val -> val.path.val.file =~ filter_fuzzy})
    let list += list_extra
  endif
  return list
endfunction

function! s:GetSearchFilesByFilter(initial_list, input)
  if exists('*matchfuzzy')
    return s:GetSearchFilesByMatchFuzzy(a:initial_list, a:input)
  elseif a:input =~ '[^\\]/$'
    " Match directory only
    return s:GetSearchFilesByFilterForDirectory(a:initial_list, a:input)
  else
    " Match filename, directory excluded by default for performance
    return s:GetSearchFilesByFilterForAll(a:initial_list, a:input)
  endif
endfunction

" Rank all files with the built-in fuzzy matcher, best first. It is written
" in C, about 5 to 10 times faster than the passes in VimL, and scores
" consecutive characters, word starts and camelCase. Input containing '/'
" matches the path relative to the project, e.g. 'pkg3/rout'.
function! s:GetSearchFilesByMatchFuzzy(initial_list, input)
  if empty(a:input)
    return copy(a:initial_list)
  endif

  let [files, dirs] = s:SplitFilesAndDirectories(a:initial_list)

  " 'name/': directories only, by name
  if a:input =~ '[^\\]/$'
    return matchfuzzy(dirs, a:input[:-2], {'key': 'file'})
  endif

  " Files first: they are what is searched for most of the time
  if stridx(a:input, '/') == -1
    return matchfuzzy(files, a:input, {'key': 'file'})
          \+ matchfuzzy(dirs, a:input, {'key': 'file'})
  endif

  call s:AddRelativePath(a:initial_list)
  return matchfuzzy(files, a:input, {'key': 'rel'})
        \+ matchfuzzy(dirs, a:input, {'key': 'rel'})
endfunction

" [files, directories] of a:list, cached while the list is the same. fd
" marks directories; otherwise isdirectory() is called once per item
function! s:SplitFilesAndDirectories(list)
  if exists('s:split_source') && s:split_source is a:list
    return s:split_result
  endif

  " A list from fd marks every directory, so an unmarked item is a file.
  " Otherwise ask the file system. String expressions are evaluated in C,
  " much faster than a loop here
  if a:list is get(s:, 'initial_list', v:null) && s:initial_list_marks_dirs
    let dirs = filter(copy(a:list), 'get(v:val, "dir", 0)')
    let files = filter(copy(a:list), '!get(v:val, "dir", 0)')
  else
    let Fullpath = function('s:GetFileFullpath')
    let dirs = filter(copy(a:list), {_, val -> get(val, 'dir', isdirectory(Fullpath(val)))})
    let files = filter(copy(a:list), {_, val -> !get(val, 'dir', isdirectory(Fullpath(val)))})
  endif
  let s:split_source = a:list
  let s:split_result = [files, dirs]
  return s:split_result
endfunction

" Add 'rel', the path relative to the project, once per file list
function! s:AddRelativePath(list)
  if empty(a:list) || has_key(a:list[0], 'rel')
    return
  endif
  call map(a:list, {_, val -> extend(val,
        \{'rel': empty(val.path) ? val.file : val.path.'/'.val.file})})
endfunction

function! s:GetMaxShowFiles()
  return (s:GetMaxHeight() - 1) * 3
endfunction

function! s:GetSearchFiles(input)
  let oldfiles = s:GetSearchFilesByOldFiles(a:input)
  let files = s:GetSearchFilesResultList(a:input)

  let max_length = s:GetMaxShowFiles()
  if len(files) > max_length
    let files = files[0:max_length-1]
  endif
  if empty(a:input)
    call s:SortByFileThenDirectory(files)
  endif
  let files = oldfiles + files
  call s:UniqueList(files)

  if len(files) > max_length
    let files = files[0:max_length-1]
    let files[-1].more = 1
  else
    if len(files) > 0
      let files[-1].more = 0
    endif
  endif
  if len(oldfiles) > 0
    let oldfiles[len(oldfiles)-1].recent = 1
  endif

  call reverse(files)
  return files
endfunction

" Items are {'file': name, 'path': parent, 'rel': path in the project}. fd
" prints directories with a trailing slash: strip it so a directory gets its
" name as 'file', and mark it with 'dir'. Kept to one lambda without calls
" to other functions, as this runs once per file of the project.
function! s:MapSearchFiles(list)
  call map(a:list, {idx, val -> val[-1:] ==# '/' || val[-1:] ==# '\'
        \? {
        \  'file': fnamemodify(val[:-2], ':t'),
        \  'path': fnamemodify(val[:-2], ':h:s+\./\|\.\\\|^\.$++'),
        \  'rel': val[:-2],
        \  'dir': 1,
        \}
        \: {
        \  'file': fnamemodify(val, ':t'),
        \  'path': fnamemodify(val, ':h:s+\./\|\.\\\|^\.$++'),
        \  'rel': val,
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

function! s:GetStrIndex(string, substring)
  return stridx(a:string, a:substring)
endfunction

function! s:SortFilesList(input, a1, a2)
  let file1 = tolower(a:a1.file)
  let file2 = tolower(a:a2.file)
  let input = tolower(a:input)
  let first = input[0]

  " Prioritize filename which contains input when input len > 2
  if len(a:input) > 2
    let index1 = s:GetStrIndex(file1, input)
    let index2 = s:GetStrIndex(file2, input)

    if index1 != -1 && index2 != -1
      return index1 - index2
    elseif index1 == -1
      return 1
    elseif index2 == -1
      return -1
    endif
  endif

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

function! s:GetSearchFilesResult(input)
  let files = s:GetSearchFiles(a:input)
  let min_col_width = s:GetMaxWidth() / 4
  let max_col_width = s:GetMaxWidth() / 8 * 5
  let columns = project#list#Tabulate(files, ['file', 'path'], min_col_width, max_col_width)
  let display = s:GetSearchFilesDisplay(files, columns)
  return [files, display]
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

function! s:GetExclude()
  return copy(project#config#Get('search_exclude'))
endfunction

function! s:GetInclude()
  return project#config#Get('search_include')
endfunction

function! s:GetMaxHeight()
  return project#list#State().max_height
endfunction

function! s:GetMaxWidth()
  return project#list#State().max_width
endfunction
