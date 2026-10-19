let s:find_in_files_show_max = 200
let s:find_in_files_stop_max = 100000
let s:update_timer = 0
let s:dismissed_find_replace = 0
" Background search with rg, ag or grep, see s:StartGrep()
let s:grep_job = v:null
let s:grep_id = 0
let s:grep_ctx = {}

function! project#find_in_files#Run(...)
  if !project#util#RequireProject()
    return
  endif

  let OpenHandler = function('s:OnOpen')
  call project#list#Open({
        \'type': 'FIND_IN_FILES',
        \'prompt': 'Find in files:',
        \'mappings': project#config#Get('list_mappings_find_in_files'),
        \'init_input': s:GetInitInput(a:000),
        \'Init': function('s:Init'),
        \'Update': function('s:UpdateTimer'),
        \'Open': function('s:Open'),
        \'handlers': {
        \  'replace_prompt': function('s:OnReplacePrompt'),
        \  'replace_dismiss_item': function('s:OnReplaceDismiss'),
        \  'replace_confirm': function('s:OnReplaceConfirm'),
        \  'open': OpenHandler,
        \  'open_split': OpenHandler,
        \  'open_vsplit': OpenHandler,
        \  'open_tabedit': OpenHandler,
        \},
        \'Highlight': function('s:Highlight'),
        \'save_history': {input -> !empty(input)},
        \'Close': function('s:StopGrep'),
        \})
endfunction

function! s:Highlight(state)
  let a:state.first_column_pattern = '^'.a:state.column_pattern
  highlight link FirstColumn Keyword
  highlight link SecondColumn Normal
endfunction

" The input given as argument, or the visual selection when called on a range
function! s:GetInitInput(args)
  if len(a:args) != 2
    return ''
  endif

  let input = a:args[0]
  let range = a:args[1]

  if !empty(input)
    return input
  endif

  if range > 0
    let saved = @z
    normal! gv"zy
    let input = @z
    let @z = saved
    return input
  endif

  return ''
endfunction

function! s:Init(input)
  let s:list = []
  let s:dismissed_find_replace = 0

  call s:Update(a:input, 1, 0)

  " When restored from history, show its results but with an empty input
  " so that typing starts a new search
  let state = project#list#State()
  if state.from_history
    let state.input = -1
    return ''
  endif
endfunction

function! s:UpdateTimer(input)
  call timer_stop(s:update_timer)
  if !s:ShouldRun(a:input) || empty(a:input)
    call s:Update(a:input, 0, 0)
  else
    let s:update_timer = timer_start(100, function('s:Update', [a:input, 0]))
  endif
endfunction

function! s:Update(full_input, is_init, id)
  " The timer may fire after the list has closed
  if !project#list#IsCurrentListBuffer()
    return
  endif

  let should_run = s:ShouldRun(a:full_input)
  let [search, replace] = s:ParseInput(a:full_input)
  let should_redraw = s:ShouldRedrawWithReplace(search, replace)
  let state = project#list#State()

  if should_run
    let replace_mode = s:IsReplaceInitiallyAdded(a:full_input)
    if s:CanGrepInBackground(search)
      " Keep the previous results until the new ones arrive
      call s:StartGrep(search, replace_mode)
    else
      call s:StopGrep()
      let s:list = s:GetResult(search, a:full_input)
    endif
    let display = s:GetDisplay(s:list, search, replace)
    let state.input = search
    if replace_mode
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
  let state.list = s:list

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
  call s:StopGrep()
  let open_type = substitute(a:open_cmd, 'open_\?', '', '')
  if open_type == ''
    let open_type = 'edit'
  endif

  let file = $vim_project.'/'.a:target.file
  let lnum = has_key(a:target, 'lnum') ? a:target.lnum : 1
  execute open_type.' +'.lnum fnameescape(file)
endfunction

function! s:ShowResult(display, search, replace, full_input, id)
  if !project#list#IsCurrentListBuffer()
    return
  endif

  call project#list#Show(a:display, a:search)
  call project#RemoveEmptyLines()
  call project#list#HighlightCurrentLine(len(a:display))
  call s:HighlightSearchAsPattern(a:search)
  call s:HighlightReplaceChars(a:search, a:replace)
  call project#list#HighlightNoResults()
  call project#list#HighlightExtraInfo()
  call project#HighlightIcon()
  call project#list#RedrawInputLine()
endfunction

" c-r: append the ' => ' separator so that what follows is the replacement
function! s:OnReplacePrompt(state)
  let input = a:state.user_input
  let separator = s:GetSeparator()
  if stridx(input, separator) == -1
    let a:state.user_input = input.separator
  endif
endfunction

" Separates search and replace in the input. Configurable so that code
" containing the default ' => ' can still be searched
function! s:GetSeparator()
  let separator = project#config#Get('find_replace_separator')
  return empty(separator) ? ' => ' : separator
endfunction

" c-d: remove the selected line or file from the replace list
function! s:OnReplaceDismiss(state)
  call s:DismissFindReplaceItem()
endfunction

" c-y: replace in all listed lines, then close
function! s:OnReplaceConfirm(state)
  if !s:HasReplace(a:state.user_input)
    return
  endif

  call s:ConfirmFindReplace(a:state.user_input)
  return 'close'
endfunction

" open*: replace first if a replacement was given, then open the target
function! s:OnOpen(state)
  if s:HasReplace(a:state.user_input)
    call s:ConfirmFindReplace(a:state.user_input)
  endif
  return 'open'
endfunction

function! s:TryHistory(search, replace)
  let history = project#list#GetHistory('FIND_IN_FILES')
  if project#list#IsShowHistoryList(a:search) && !empty(history)
    return s:ParseInput(history.input)
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
  execute 'silent! 1match FirstColumn /'.project#list#State().first_column_pattern.'/'
endfunction

function! s:HighlightReplaceChars(search, replace)
  if a:replace == ''
    return
  endif

  let pattern = s:GetSearchPattern(a:search)
  execute 'silent! 3match BeforeReplace /'.pattern.'/'
  execute 'silent! 2match AfterReplace /'.pattern.'\zs\V'.a:replace.'/'
  execute 'silent! 1match FirstColumn /'.project#list#State().first_column_pattern.'/'
endfunction

function! s:HasReplace(input)
  let [search, replace] = s:GetSearchAndReplace(a:input)
  return !empty(replace)
endfunction

function! s:ConfirmFindReplace(input)
  call s:WaitGrep()
  let [search, replace] = s:GetSearchAndReplace(a:input)
  call s:RunReplaceAll(search, replace)
endfunction

function! s:GetSearchAndReplace(input)
  let [current_search, current_replace] = s:ParseInput(a:input)
  let [search, replace] = s:TryHistory(current_search, current_replace)
  return [search, replace] 
endfunction

function! s:ParseInput(input)
  " Match the separator literally, it may contain regexp characters
  let inputs = split(a:input, '\V'.escape(s:GetSeparator(), '\'))

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


function! s:DismissFindReplaceItem()
  let target = project#list#GetTarget()
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
  let index = project#list#GetCurrentIndex()
  call remove(s:list, index)
  call s:RemoveFileWithoutItem()
  call s:UpdateOffsetAfterRemoveTarget()
endfunction

function! s:UpdateOffsetAfterRemoveTarget()
  let state = project#list#State()
  if state.offset < len(s:list) - 2
    let state.offset += 1
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
  let target = project#list#GetTarget()
  if s:IsFileItem(target)
    let current_index = project#list#GetCurrentIndex()
    let next_file_index = s:GetNextFileIndex(current_index)
    if next_file_index - current_index < 2
      call s:RemoveTarget()
    endif
  endif
endfunction

function! s:RemoveFile()
  let index = project#list#GetCurrentIndex()
  let next_file_index = s:GetNextFileIndex(index)
  call s:RemoveRange(index, next_file_index - 1)
  call project#list#UpdateOffsetByIndex(index)
endfunction

function! s:RemoveRange(start, end)
  if a:start < a:end
    call remove(s:list, a:start, a:end)
  endif
endfunction

function! s:RunReplaceAll(search, replace)
  let pattern = s:GetSearchPattern(a:search)
  let groups = s:GroupLineItemsByFile(s:list)
  let result = s:ReplaceInFiles(groups, pattern, a:replace)
  call s:ReloadChangedBuffers(result.changed)
  " Report after the list has closed
  call timer_start(100, function('s:ReportReplace', [result]))
endfunction

" [{'file': relative path, 'items': [line items]}, ...] in list order
function! s:GroupLineItemsByFile(list)
  let groups = []
  let index_by_file = {}
  for item in a:list
    if !s:IsFileLineItem(item)
      continue
    endif
    if !has_key(index_by_file, item.file)
      let index_by_file[item.file] = len(groups)
      call add(groups, {'file': item.file, 'items': []})
    endif
    call add(groups[index_by_file[item.file]].items, item)
  endfor
  return groups
endfunction

" Replace in each file with one read and one write. A line is only replaced
" when it still reads as it did in the search result, and a file with
" unsaved changes in a buffer is left alone. Line endings and a missing
" final newline are kept by reading and writing in binary mode.
"
" Returns {
"   'lines':   number of lines replaced,
"   'changed': full paths of files written,
"   'stale':   'file:lnum' of lines skipped because they changed,
"   'unsaved': files skipped because of unsaved buffer changes,
"   'failed':  files that could not be written,
" }
function! s:ReplaceInFiles(groups, pattern, replace)
  let result = {'lines': 0, 'changed': [], 'stale': [], 'unsaved': [], 'failed': []}
  let total = len(a:groups)
  let index = 0

  for group in a:groups
    let index += 1
    redraw
    call project#InfoEcho('Replacing files: '.index.' of '.total)

    let path = s:GetProjectFilePath(group.file)
    let bufnr = s:GetLoadedBufnr(path)
    if bufnr != -1 && getbufvar(bufnr, '&modified')
      call add(result.unsaved, group.file)
      continue
    endif
    if !filereadable(path)
      call extend(result.stale, map(copy(group.items), {_, item -> item.file.':'.item.lnum}))
      continue
    endif

    let lines = readfile(path, 'b')
    let replaced = 0
    for item in group.items
      let idx = str2nr(item.lnum) - 1
      if idx < 0 || idx >= len(lines)
            \|| s:RemoveTrailingCR(lines[idx]) !=# s:RemoveTrailingCR(item.line)
        call add(result.stale, item.file.':'.item.lnum)
        continue
      endif

      let body = s:RemoveTrailingCR(lines[idx])
      let cr = lines[idx][len(body):]
      let new_body = s:GetReplacedLine(body, a:pattern, a:replace, 0)
      if new_body !=# body
        let lines[idx] = new_body.cr
        let replaced += 1
      endif
    endfor

    if replaced == 0
      continue
    endif
    try
      if writefile(lines, path, 'b') != 0
        throw 'write failed'
      endif
      let result.lines += replaced
      call add(result.changed, path)
    catch
      call add(result.failed, group.file)
    endtry
  endfor

  return result
endfunction

function! s:RemoveTrailingCR(line)
  return substitute(a:line, '\r$', '', '')
endfunction

function! s:GetProjectFilePath(file)
  return $vim_project.'/'.a:file
endfunction

" bufnr of the loaded buffer editing a:path, or -1
function! s:GetLoadedBufnr(path)
  let target = resolve(fnamemodify(a:path, ':p'))
  for buf in getbufinfo({'bufloaded': 1})
    if !empty(buf.name) && resolve(fnamemodify(buf.name, ':p')) ==# target
      return buf.bufnr
    endif
  endfor
  return -1
endfunction

" Reload unmodified buffers of written files without the W11 prompt
function! s:ReloadChangedBuffers(paths)
  let autoread_save = &g:autoread
  set autoread
  try
    for path in a:paths
      let bufnr = s:GetLoadedBufnr(path)
      if bufnr != -1 && !getbufvar(bufnr, '&modified')
        silent! execute 'checktime' bufnr
      endif
    endfor
  finally
    let &g:autoread = autoread_save
  endtry
endfunction

function! s:ReportReplace(result, ...)
  let message = 'Replaced '.a:result.lines.' line(s) in '
        \.len(a:result.changed).' file(s)'
  call project#Info(message)
  if !empty(a:result.unsaved)
    call project#Warn('Skipped files with unsaved changes: '
          \.join(a:result.unsaved, ', '))
  endif
  if !empty(a:result.stale)
    let shown = a:result.stale[0:4]
    let more = len(a:result.stale) > 5 ? ', ...' : ''
    call project#Warn('Skipped '.len(a:result.stale)
          \.' line(s) changed since the search: '.join(shown, ', ').more)
  endif
  if !empty(a:result.failed)
    call project#Warn('Failed to write: '.join(a:result.failed, ', '))
  endif
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

  if project#HasMoreOnList(a:list)
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
    if len(line) > &columns
      let line = line[0:&columns]
    endif
    if a:show_replace
      let line = s:GetReplacedLine(line, a:pattern, a:replace, 1)
    endif
    return '  '.line
  endif
endfunction

" a:replace is inserted as typed. With a:add the match is kept in front of
" it, to show both in the list
function! s:GetReplacedLine(line, pattern, replace, add)
  let replace = a:replace
  if a:add
    return substitute(a:line, a:pattern, {m -> m[0].replace}, 'g')
  endif
  return substitute(a:line, a:pattern, {m -> replace}, 'g')
endfunction

function! s:TryExternalGrepProgram()
  " Try rg, ag, grep, vimgrep in order
  let grep_cmd_map = {
        \'rg': function('s:GetRgCmd'),
        \'ag': function('s:GetAgCmd'),
        \'grep': function('s:GetGrepCmd'),
        \}

  let grep_program = project#util#PickExecutable(['rg', 'ag', 'grep'], 'vimgrep')
  let s:grep_cmd_func = get(grep_cmd_map, grep_program, 0)
  return grep_program
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

  let search_arg = '--line-number --recursive --binary-files=without-match'
  if !project#Include(a:flags, 'C')
    let search_arg .= ' --ignore-case'
  endif
  if project#Include(a:flags, 'E')
    let search_arg .= ' --extended-regexp'
  else
    let search_arg .= ' --fixed-strings'
  endif

  let cmd = 'grep '.search_arg.' '.include_arg.' '.exclude_arg.' -- '.a:pattern
  return cmd
endfunction

function! s:GetRgCmd(pattern, flags)
  let include = s:GetInclude()
  " Remove '.', as rg does not support '{./**}'
  call filter(include, {_, val -> !empty(val) && val != '.' && val != './'})

  if len(include)
    let include_pattern = map(include, {_, val -> val.'/**' })
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
  let pattern = shellescape(a:search)
  let cmd = s:grep_cmd_func(pattern, a:flags)

  let output = project#RunShellCmd(cmd)
  let result = s:GetResultFromGrepOutput(a:search, a:full_input, output)
  return result
endfunction


function! s:SetGrepOutputLength(input, full_input, output, ...)
  let output = a:output
  let output_len = len(output)
  let more = 0

  if a:0
    let replace_initially_added = a:1
  else
    let replace_initially_added = s:IsReplaceInitiallyAdded(a:full_input)
  endif

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

  let result = map(output, {_, val -> s:ParseGrepLine(val)})

  if more
    let result[0].more = more
  endif
  return result
endfunction

" Parse 'file:lnum:text'. Text may contain any ':', e.g. 'std::io'
function! s:ParseGrepLine(line)
  let parts = matchlist(a:line, '^\(.\{-}\):\(\d\+\):\(.*\)$')
  if !empty(parts)
    return {'file': parts[1], 'lnum': parts[2], 'line': parts[3]}
  endif
  " Not a match line, e.g. an error message: show it as is
  let segments = split(a:line, ':', 1)
  return {'file': segments[0], 'lnum': 0, 'line': join(segments[1:], ':')}
endfunction

function! s:RunVimGrep(search, flags, full_input)
  let original_wildignore = &wildignore
  for exclude in s:GetExclude()
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

function! s:RemoveProjectPath(path)
  let result = substitute(a:path, $vim_project, '', '')
  if result != a:path
    let result = substitute(result, '^/', '', '')
  endif
  return result
endfunction

" ---------------------------------------------------------------- background

" rg on a large project takes a second or more. Run it as a job so typing
" never waits: a new search stops the previous one, and a normal search
" stops as soon as it has more lines than can be shown.
function! s:CanGrepInBackground(search)
  if !exists('s:grep_cmd_func')
    call s:TryExternalGrepProgram()
  endif
  let raw_search = s:RemoveSearchFlags(a:search)
  return s:grep_cmd_func isnot 0
        \&& (exists('*job_start') || exists('*jobstart'))
        \&& len(raw_search) > 1
endfunction

function! s:StartGrep(search, replace_mode)
  call s:StopGrep()
  let s:grep_id += 1
  let id = s:grep_id
  let flags = s:GetSearchFlags(a:search)
  let cmd = s:grep_cmd_func(shellescape(s:RemoveSearchFlags(a:search)), flags)
  " One line more than needed tells there are more
  let limit = a:replace_mode ? s:find_in_files_stop_max + 1 : s:find_in_files_show_max + 2
  let s:grep_ctx = {
        \'id': id,
        \'search': a:search,
        \'replace_mode': a:replace_mode,
        \'limit': limit,
        \'lines': [],
        \'errors': [],
        \'partial': '',
        \'stopped': 0,
        \'done': 0,
        \}
  let shell_cmd = [&shell, &shellcmdflag, cmd]

  if exists('*job_start')
    let s:grep_job = job_start(shell_cmd, {
          \'cwd': $vim_project,
          \'in_io': 'null',
          \'out_mode': 'nl',
          \'err_mode': 'nl',
          \'out_cb': {_, line -> s:OnGrepLines(id, [line])},
          \'err_cb': {_, line -> s:OnGrepError(id, [line])},
          \'close_cb': {_ -> s:OnGrepDone(id)},
          \})
  else
    " rg searches stdin when it is a pipe: give it none
    let s:grep_job = jobstart(shell_cmd, {
          \'cwd': $vim_project,
          \'stdin': 'null',
          \'on_stdout': {_, data, __ -> s:OnNvimGrepOutput(id, data)},
          \'on_stderr': {_, data, __ -> s:OnGrepError(id, data)},
          \'on_exit': {_, status, __ -> s:OnGrepDone(id)},
          \})
  endif
endfunction

" Neovim passes chunks: the first item continues the previous last one
function! s:OnNvimGrepOutput(id, data)
  if a:id != s:grep_id || empty(a:data)
    return
  endif
  let data = copy(a:data)
  let data[0] = s:grep_ctx.partial.data[0]
  let s:grep_ctx.partial = remove(data, -1)
  call s:OnGrepLines(a:id, data)
endfunction

function! s:OnGrepLines(id, lines)
  let ctx = s:grep_ctx
  if a:id != s:grep_id || ctx.stopped
    return
  endif
  call extend(ctx.lines, filter(a:lines, '!empty(v:val)'))
  if len(ctx.lines) >= ctx.limit
    let ctx.stopped = 1
    call s:KillGrepJob()
    " The job may not report its end once killed
    call s:OnGrepDone(a:id)
  endif
endfunction

function! s:OnGrepError(id, lines)
  if a:id == s:grep_id
    call extend(s:grep_ctx.errors, filter(copy(a:lines), '!empty(v:val)'))
  endif
endfunction

function! s:OnGrepDone(id)
  let ctx = s:grep_ctx
  if a:id != s:grep_id || ctx.done
    return
  endif
  let ctx.done = 1
  let s:grep_job = v:null
  if !empty(ctx.partial)
    call add(ctx.lines, ctx.partial)
  endif

  let [output, more] = s:SetGrepOutputLength(ctx.search, '', ctx.lines, ctx.replace_mode)
  let result = map(output, {_, val -> s:ParseGrepLine(val)})
  if more && !empty(result)
    let result[0].more = more
  endif
  let s:list = s:GetGroupedList(result)

  if !project#list#IsOpen('FIND_IN_FILES')
    return
  endif
  if empty(s:list) && !empty(ctx.errors)
    call project#Warn(ctx.errors[0])
  endif
  let state = project#list#State()
  let state.list = s:list
  " The replace text may have been typed while searching
  let [_, replace] = s:ParseInput(state.user_input)
  let display = s:GetDisplay(s:list, ctx.search, replace)
  call s:ShowResult(display, ctx.search, replace, state.user_input, 0)
endfunction

function! s:IsGrepRunning()
  return !empty(s:grep_ctx) && !s:grep_ctx.done && s:grep_job isnot v:null
endfunction

function! s:KillGrepJob()
  if s:grep_job is v:null
    return
  endif
  if exists('*job_stop')
    call job_stop(s:grep_job, 'kill')
  else
    silent! call jobstop(s:grep_job)
  endif
endfunction

function! s:StopGrep(...)
  let s:grep_id += 1
  call s:KillGrepJob()
  let s:grep_job = v:null
endfunction

" Wait for a running search, e.g. before replacing with its results
function! s:WaitGrep()
  let tries = 0
  while s:IsGrepRunning() && tries < 6000
    sleep 10m
    let tries += 1
  endwhile
endfunction

function! s:IsReplaceInitiallyAdded(input)
  let [_, replace] = s:ParseInput(a:input)
  let has_separator = stridx(a:input, s:GetSeparator()) != -1
  return has_separator && empty(replace) && s:GetReplace() == -1
endfunction

function! s:ShouldRun(input)
  let [search, replace] = s:ParseInput(a:input)
  let state = project#list#State()
  let search_changed = has_key(state, 'input') && search != state.input
        \&& !project#list#IsShowHistoryList(search)
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
  return a:replace != s:GetReplace() && !project#list#IsShowHistoryList(a:input)
endfunction

function! s:HasDismissed()
  return s:dismissed_find_replace
endfunction

function! s:SetReplace(replace)
  let state = project#list#State()
  let state.replace = a:replace
endfunction

function! s:GetReplace()
  return project#list#State().replace
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
  return copy(project#config#Get('find_in_files_include'))
endfunction

function! s:GetExclude()
  return copy(project#config#Get('find_in_files_exclude'))
endfunction
