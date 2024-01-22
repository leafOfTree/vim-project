let s:find_in_files_show_max = 200
let s:find_in_files_stop_max = 100000
let s:update_timer = 0
let s:search_replace_separator = ' => '
let s:dismissed_find_replace = 0

function! project#find_in_files#Run(...)
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:SetInitInput(a:000)
  call project#PrepareListBuffer('Find in files:', 'FIND_IN_FILES')

  let Init = function('s:Init')
  let Update = function('s:UpdateTimer')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:SetInitInput(args)
  if len(a:args) != 2
    return
  endif

  let input = a:args[0]
  let range = a:args[1]

  if !empty(input)
    call project#SetVariable('init_input', input)
    return
  endif

  if range > 0
    let saved = @z
    normal! gv"zy
    call project#SetVariable('init_input', @z)
    let @z = saved
    return
  endif
endfunction

function! s:Init(input)
  let s:list = []
  let s:dismissed_find_replace = 0

  return s:Update(a:input, 1, 0)
endfunction

function! s:UpdateTimer(input)
  call timer_stop(s:update_timer)
  if !s:ShouldRun(a:input) || empty(a:input)
    call s:Update(a:input, 0, 0)
  else
    let s:update_timer = timer_start(200, function('s:Update', [a:input, 0]))
  endif
endfunction

function! s:Update(full_input, is_init, id)
  let should_run = s:ShouldRun(a:full_input)
  let [search, replace] = s:ParseInput(a:full_input)
  let should_redraw = s:ShouldRedrawWithReplace(search, replace)

  if should_run
    let s:list = s:GetResult(search, a:full_input)
    let display = s:GetDisplay(s:list, search, replace)
    call project#SetVariable('input', search)
    if s:IsReplaceInitiallyAdded(a:full_input)
      call s:SetReplace(replace)
    else
      call s:SetReplace(-1)
    endif
  elseif should_redraw
    let [redraw_search, redraw_replace] = s:TryHistory(search, replace)
    let display = s:GetDisplay(s:list, redraw_search, redraw_replace)
    call s:SetReplace(replace)
  else
    let display = s:GetDisplay(s:list, search, replace)
  endif
  call project#SetVariable('list', s:list)

  " Use timer just for fluent typing. Not necessary
  let use_timer = (should_run || should_redraw) && !empty(a:full_input) && !a:is_init
  if use_timer
    call s:ShowResultTimer(display, search, replace, a:full_input)
  else
    call s:ShowResult(display, search, replace, a:full_input, 0)
  endif
endfunction

function! s:ShowResultTimer(display, search, replace, full_input)
  call timer_start(1,
        \function('s:ShowResult', [a:display, a:search, a:replace, a:full_input]))
endfunction

function! s:Open(target, open_cmd, input)
  let open_type = substitute(a:open_cmd, 'open_\?', '', '')
  if open_type == ''
    let open_type = 'edit'
  endif

  let file = $vim_project.'/'.a:target.file
  let lnum = has_key(a:target, 'lnum') ? a:target.lnum : 1
  execute open_type.' +'.lnum.' '.file
endfunction
" 
function! s:ShowResult(display, search, replace, full_input, id)
  call project#ShowInListBuffer(a:display, a:search)
  call project#HighlightCurrentLine(len(a:display))
  call s:HighlightSearchAsPattern(a:search)
  call s:HighlightReplaceChars(a:search, a:replace)
  call s:HighlighExtraInfo()
  call project#HighlightNoResults()
  call project#RedrawInputLine()
endfunction

function! s:HighlighExtraInfo()
  call matchadd('Special', ' \.\.\.more$')
endfunction

function! project#find_in_files#AddFindReplaceSeparator(input)
  if !project#Include(a:input, s:search_replace_separator)
    let input = a:input.s:search_replace_separator
  else
    let input = a:input
  endif

  return input
endfunction

function! s:TryHistory(search, replace)
  if project#IsShowHistoryList(a:search) && project#HasFindInFilesHistory()
    let input = project#GetVariable('list_history').FIND_IN_FILES.input
    return s:ParseInput(input)
  else
    return [a:search, a:replace]
  endif
endfunction

function! s:HighlightSearchAsPattern(search)
  if a:search == ''
    return
  endif

  call clearmatches()
  let pattern = s:GetSearchPattern(a:search)
  execute 'silent! 2match InputChar /'.pattern.'/'
  execute 'silent! 1match FirstColumn /'.project#GetVariable('first_column_pattern').'/'
endfunction

function! s:HighlightReplaceChars(search, replace)
  if a:replace == ''
    return
  endif

  let pattern = s:GetSearchPattern(a:search)
  execute 'silent! 3match BeforeReplace /'.pattern.'/'
  execute 'silent! 2match AfterReplace /'.pattern.'\zs\V'.a:replace.'/'
  execute 'silent! 1match FirstColumn /'.project#GetVariable('first_column_pattern').'/'
endfunction


function! project#find_in_files#ConfirmFindReplace(input)
  let [current_search, current_replace] = s:ParseInput(a:input)
  let [search, replace] =
        \s:TryHistory(current_search, current_replace)
  call s:RunReplaceAll(search, replace)
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

function! project#find_in_files#DismissFindReplaceItem()
  let target = project#GetTarget()
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

function! s:RemoveTarget()
  let index = project#GetCurrentIndex()
  call remove(s:list, index)
  call s:RemoveFileWithoutItem()
  call s:UpdateOffsetAfterRemoveTarget()
endfunction

function! s:UpdateOffsetAfterRemoveTarget()
  let offset = project#GetVariable('offset')
  if offset < len(s:list) - 2
    call project#SetVariable('offset', offset+1)
  endif
endfunction

function! s:GetNextFileIndex(index)
  for i in range(a:index+1, len(s:list)-1)
    if s:IsFileItem(s:list[i])
      return i
    endif
  endfor

  return len(s:list)
endfunction

function! s:RemoveFileWithoutItem()
  let target = project#GetTarget()
  if s:IsFileItem(target)
    let current_index = project#GetCurrentIndex()
    let next_file_index = s:GetNextFileIndex(current_index)
    if next_file_index - current_index < 2
      call s:RemoveTarget()
    endif
  endif
endfunction

function! s:RemoveFile()
  let index = project#GetCurrentIndex()
  let next_file_index = s:GetNextFileIndex(index)
  call s:RemoveRange(index, next_file_index - 1)
  call project#UpdateOffsetByIndex(index)
endfunction

function! s:RemoveRange(start, end)
  if a:start < a:end
    call remove(s:list, a:start, a:end)
  endif
endfunction

function! s:RunReplaceAll(search, replace)
  let index_line = 0
  let index_file = 0
  let total_lines = s:GetTotalReplaceLines()
  let total_files = len(s:list) - total_lines
  let pattern = s:GetSearchPattern(a:search)

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
    call project#InfoEcho('Replaced '.info_file.', '.info_line)
  endfor

  edit
  call timer_start(100, function('project#Info', ['Replaced '.info_file.', '.info_line]))
endfunction

function! s:GetSearchPattern(search)
  let flags = s:GetSearchFlags(a:search)
  let pattern_flags = ''
  if project#Include(flags, 'C')
    let pattern_flags .= '\C'
  else
    let pattern_flags .= '\c'
  endif
  if project#Include(flags, 'E')
    let pattern_flags .= '\v'
  else
    let pattern_flags .= '\V'
  endif

  let search = s:RemoveSearchFlags(a:search)
  let pattern = search
  let pattern = escape(pattern, '/')
  let pattern = substitute(pattern, '\\\$', '\\\\$', 'g')
  let pattern = s:TransformPatternOneByOne(pattern)
  return pattern_flags.pattern
endfunction

function! s:GetResult(search, full_input)
  let raw_search = s:RemoveSearchFlags(a:search)
  if raw_search == '' || len(raw_search) == 1
    return []
  endif

  let list = s:GetGrepResult(a:search, a:full_input)
  return list
endfunction

function! s:GetDisplay(list, search, replace)
  if len(a:list) == 0
    return []
  endif

  let pattern = s:GetSearchPattern(a:search)
  let show_replace = !empty(a:search) && !empty(a:replace)

  let display = map(copy(a:list),
        \function('s:GetDisplayRow', [pattern, a:replace, show_replace]))

  if project#hasMoreOnList(a:list)
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

function! s:GetDisplayRow(pattern, replace, show_replace, idx, val)
  let isFile = s:IsFileItem(a:val)
  if isFile
    let icon = project#GetIcon($vim_project.'/'.a:val.file)
    return icon.a:val.file
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

function! s:GetAgCmd(pattern, flags)
  let include = s:GetInclude()
  let include_arg = join(include, ' ')

  let exclude = s:GetExclude()
  let exclude_arg = join(
        \map(exclude,{_, val -> '--ignore-dir '.val}), ' ')

  let search_arg = '--hidden --skip-vcs-ignores'
  if project#Include(a:flags, 'C')
    let search_arg .= ' --case-sensitive'
  else
    let search_arg .= ' --ignore-case'
  endif
  if !project#Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'ag '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
  return cmd
endfunction

function! s:GetGrepCmd(pattern, flags)
  let include = s:GetInclude()
  let include_arg = join(include, ' ')
  if empty(include_arg)
    let include_arg = '.'
  endif

  let exclude = s:GetExclude()
  let exclude_arg = join(
        \map(exclude,{_, val -> '--exclude-dir '.val}), ' ')

  let search_arg = '--line-number --recursive'
  if !project#Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if !project#Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'fgrep '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
  return cmd
endfunction

function! s:GetRgCmd(pattern, flags)
  let include = s:GetInclude()
  " Remove '.', as rg does not support '{./**}'
  call filter(include, {_, val -> val != '.'})

  if len(include)
    let include_pattern = map(include, 
          \{_, val -> val.'/**' })
    let include_arg = '-g "{'.join(include_pattern, ',').'}"'
  else
    let include_arg = '-g "{**}"'
  endif

  let exclude = s:GetExclude()
  let exclude_arg = '-g "!{'.join(exclude, ',').'}"'

  let search_arg = '--line-number --no-ignore-vcs'
  if !project#Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if !project#Include(a:flags, 'E')
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'rg '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
  return cmd
endfunction

function! s:RunExternalGrep(search, flags, full_input)
  let pattern = '"'.escape(a:search, '"$').'"'
  let cmd = s:grep_cmd_func(pattern, a:flags)

  let output = project#RunShellCmd(cmd)
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

function! s:RunVimGrep(search, flags, full_input)
  let original_wildignore = &wildignore
  for exclude in s:find_in_files_exclude
    execute 'set wildignore+=*/'.exclude.'*'
  endfor

  let pattern_flag = ''
  if project#Include(a:flags, 'C')
    let pattern_flag .= '\C'
  else
    let pattern_flag .= '\c'
  endif
  if project#Include(a:flags, 'E')
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

function! s:IsReplaceInitiallyAdded(input)
  let [_, replace] = s:ParseInput(a:input)
  let has_separator = project#Include(a:input, s:search_replace_separator)
  return has_separator && empty(replace) && s:GetReplace() == -1
endfunction

function! s:ShouldRun(input)
  let [search, replace] = s:ParseInput(a:input)
  let search_changed = project#Exist('input') && search != project#GetVariable('input') 
        \&& !project#IsShowHistoryList(search)
  let replace_initially_added = s:IsReplaceInitiallyAdded(a:input)
  return search_changed || replace_initially_added
endfunction

function! s:GetSearchFlags(search)
  let case_sensitive = project#Include(a:search, '\\C')
  let use_regexp = project#Include(a:search, '\\E')

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

function! s:ShouldRedrawWithReplace(input, replace)
  if s:HasDismissed()
    return 1
  endif
  if empty(a:replace) && s:GetReplace() == -1
    return 0
  endif
  return a:replace != s:GetReplace() && !project#IsShowHistoryList(a:input)
endfunction

function! s:HasDismissed()
  return s:dismissed_find_replace
endfunction

function! s:SetReplace(replace)
  call project#SetVariable('replace', a:replace)
endfunction

function! s:GetReplace()
  return project#GetVariable('replace')
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

function! s:ReplaceEscapedChar(chars, idx, char, from, to)
  let idx = a:idx

  let char_idx = index(a:from, a:char)
  if char_idx != -1 && idx > 0
    if a:chars[idx-1] == '\'
      let a:chars[idx] = a:to[char_idx]
    endif
  endif
endfunction

function! s:GetInclude()
  return copy(project#GetVariable('find_in_files_include'))
endfunction

function! s:GetExclude()
  return copy(project#GetVariable('find_in_files_exclude'))
endfunction
