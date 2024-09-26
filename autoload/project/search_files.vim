let s:search_files_sort_max = 1000

function! project#search_files#Run()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call project#PrepareListBuffer('Search files by name:', 'SEARCH_FILES')

  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! project#search_files#reset()
  unlet! s:initial_list
endfunction

function! s:Init(input)
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let [list, display] = s:GetSearchFilesResult(a:input)
  call project#SetVariable('input', a:input)
  call project#SetVariable('list', list)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
  call project#HighlightIcon()
  call project#HighlightExtraInfo()
endfunction

function! s:Open(target, open_cmd, input)
  let cmd = substitute(a:open_cmd, 'open_\?', '', '')
  let cmd = cmd == '' ? 'edit' : cmd
  let file = $vim_project.'/'.a:target.path.'/'.a:target.file
  execute cmd.' '.file
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
  if project#hasMoreOnList(a:list)
    let a:display[0] = substitute(a:display[0], '\s*$', '  ...more', 'g')
  endif

  let recent_index = s:GetRecentIndex(a:list)
  if recent_index != -1
    let a:display[recent_index] .= ''
  endif
endfunction

function! s:GetSearchFilesDisplay(list)
  let display = map(copy(a:list), function('s:GetSearchFilesDisplayRow'))
  call s:DecorateSearchFilesDisplay(a:list, display)
  return display
endfunction

function! s:GetFileFullpath(value)
  return $vim_project.'/'.a:value.path.'/'.a:value.file
endfunction

function! s:GetSearchFilesDisplayRow(idx, value)
  let fullpath = s:GetFileFullpath(a:value)
  if isdirectory(fullpath)
    let file = substitute(a:value.__file, '\S\zs\s\|\S\zs$', '/', '')
  else
    let file = a:value.__file
  endif
  let icon = project#GetIcon(fullpath)
  return icon.file.'  '.a:value.__path
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
  let pattern = join(split(a:input, '\zs'), '.*')
  call filter(a:oldfiles,
        \{_, val -> val.file =~ pattern})
endfunction

function! s:GetFilesByFind()
  let include = join(s:GetInclude(), ' ')

  let search_exclude = s:GetExclude()
  let exclude_string = join(map(search_exclude, {_, val -> '-name "'.val.'"'}), ' -o ')
  let exclude = '\( '.exclude_string.' \) -prune -false -o '

  let filter = '-ipath "*"'
  let cmd = 'find '.include.' -mindepth 1 '.exclude.filter
  let result = project#RunShellCmd(cmd)
  return result
endfunction

function! s:GetFilesByFd()
  let include = join(s:GetInclude(), ' ')

  let search_exclude = s:GetExclude()
  let exclude = join(map(search_exclude, {_, val -> '-E "'.val.'"'}), ' ')

  let cmd = 'fd -HI '.exclude.' . '.include
  let result = project#RunShellCmd(cmd)
  return result
endfunction

function! s:GetFilesByGlob()
  let original_wildignore = &wildignore
  let cwd = getcwd()
  execute 'cd '.$vim_project
  for exclue in s:GetExclude()
    execute 'set wildignore+=*/'.exclue.'*'
  endfor

  let result = []
  for path in s:GetInclude()
    let result = result + glob(path.'/**/*', 0, 1)
  endfor

  execute 'cd '.cwd
  let &wildignore = original_wildignore
  return result
endfunction

function! s:GetSearchFilesResultList(input)
  if !exists('s:initial_list')
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
  let s:initial_list = result
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

function! s:GetSearchFilesByDirectory(val, filter)
  let path = a:val.path
  let file = a:val.file
  let fullpath = s:GetFileFullpath(a:val)

  return isdirectory(fullpath) && file =~ a:filter
endfunction

function! s:GetSearchFilesByFilterForDirectory(input)
  let list = []
  let filter = substitute(a:input, '/$', '', '')
  let list = filter(copy(s:initial_list), {_, val -> s:GetSearchFilesByDirectory(val, filter)})

  if len(list) < s:GetMaxHeight()
    call s:SortSearchFilesList(list, filter)

    let filter_fuzzy = join(split(filter, '\zs'), '.*')
    let list_extra = filter(copy(s:initial_list), {_, val -> s:GetSearchFilesByDirectory(val, filter_fuzzy)})
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
    let list = filter(copy(s:initial_list), {_, val -> val.file =~ filter_start})
  endif

  if len(list) < s:GetMaxHeight()
    let list = filter(copy(s:initial_list), {_, val -> val.file =~ filter_origin})
    call s:SortSearchFilesList(list, a:input)
  endif

  if len(list) < s:GetMaxHeight()
    let filter_fuzzy = join(split(a:input, '\zs'), '.*')
    let list_extra = filter(copy(s:initial_list), {_, val -> val.file =~ filter_fuzzy})
    call s:SortSearchFilesList(list_extra, a:input)
    let list += list_extra
  endif

  " Match path and file if list is short
  if len(list) < s:GetMaxHeight()
    let list_extra = filter(copy(s:initial_list), {_, val -> val.path.val.file =~ filter_origin})
    let list += list_extra
  endif

  " Fuzzy match path and file if list is short
  if len(list) < s:GetMaxHeight()
    let list_extra = filter(copy(s:initial_list), {_, val -> val.path.val.file =~ filter_fuzzy})
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

function! s:GetMaxShowFiles()
  return (s:GetMaxHeight() - 1) * 3
endfunction

function! s:GetSearchFiles(input)
  let oldfiles = s:GetSearchFilesByOldFiles(a:input)
  let files = s:GetSearchFilesResultList(a:input)

  let max_length = s:GetMaxShowFiles()
  let files = files[0:max_length-1]
  if empty(a:input)
    call s:SortByFileThenDirectory(files)
  endif
  let files = oldfiles + files
  call s:UniqueList(files)

  if len(files) > max_length
    let files = files[0:max_length-1]
    let files[-1].more = 1
  else
    let files[-1].more = 0
  endif
  if len(oldfiles) > 0
    let oldfiles[len(oldfiles)-1].recent = 1
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

function! s:SortFilesList(input, a1, a2)
  let file1 = a:a1.file
  let file2 = a:a2.file
  let first = '\c'.a:input[0]

  let start1 = match(file1, first)
  let start2 = match(file2, first)
  if start1 == start2
    " Prioritize filename which contains input when input len > 2
    if len(a:input) > 2
      let lower_input = tolower(a:input)
      if stridx(tolower(file1), lower_input) != -1
        return -1
      endif
      if stridx(tolower(file2), lower_input) != -1
        return 1
      endif
    endif

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
  call project#Tabulate(files, ['file', 'path'], min_col_width, max_col_width)
  let display = s:GetSearchFilesDisplay(files)
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
  return copy(project#GetVariable('search_exclude'))
endfunction

function! s:GetInclude()
  return project#GetVariable('search_include')
endfunction

function! s:GetMaxHeight()
  return project#GetVariable('max_height')
endfunction

function! s:GetMaxWidth()
  return project#GetVariable('max_width')
endfunction
