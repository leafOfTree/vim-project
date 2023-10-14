let s:list = []
let s:display = []
let s:input = ''
let s:changes_buffer = 'Changes [Press Enter to view diff or take action]'
let s:current_file = ''

function! project#git#file_history()
  call s:CloseFileHistory()

  let s:current_file = expand('%:p')
  let filename = expand('%:t')
  if !filereadable(s:current_file)
    call project#Warn('Open a file first to show history')
    return
  endif

  call project#SetVariable('initial_height', winheight(0) - 5)
  call project#PrepareListBuffer('History of '.filename.':' , 'GIT_FILE_HISTORY')
  let Init = function('s:InitFileHistory')
  let Update = function('s:UpdateFileHistory')
  let Open = function('s:OpenFileHistory')
  let Close = function('s:CloseFileHistory')
  call project#RenderList(Init, Update, Open, Close)
endfunction

function! s:InitFileHistory(input)
  let format = "%s ||| %aN ||| %ae ||| %ad ||| %h"
  let cmd = "git log --pretty=format:'".format."' --date=relative ".s:current_file
  let logs = project#RunShellCmd(cmd)
  let s:list = s:GetFileHistoryList(logs)
  call s:UpdateFileHistory(a:input)
endfunction

function! s:UpdateFileHistory(input)
  call s:UpdateLog(a:input)
  call s:ShowCurrentChange()
endfunction

function! s:ShowCurrentChange()
  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  let format = "%s\ncommit %h\n"
  let cmd = "git show --pretty=format:'".format."' ".revision.hash.' -- '.s:current_file
  let changes = systemlist(cmd)
  call s:OpenBuffer('[diff]', '[diff]', 'vertical')
  call append(0, changes)
  normal! gg
  silent 4,7d
  setlocal buftype=nofile bufhidden=wipe nobuflisted filetype=git
  setlocal nowrap
  wincmd h
endfunction

function! s:OpenFileHistory(revision, cmd, input)
  " just keep [diff] window
endfunction

function! s:CloseFileHistory()
  call s:CloseBuffer('[diff]')
endfunction

function! project#git#log()
  call s:CloseChangesBuffer()

  call project#PrepareListBuffer('Search log:', 'GIT_LOG')
  let Init = function('s:InitGitLog')
  let Update = function('s:UpdateGitLog')
  let Open = function('s:OpenGitLog')
  let Close = function('s:CloseGitLog')
  call project#RenderList(Init, Update, Open, Close)
endfunction


function! s:InitGitLog(input)
  let format = "%s ||| %aN ||| %ae ||| %ad ||| %h"
  let cmd = "git log --pretty=format:'".format."' --date=relative"
  let logs = project#RunShellCmd(cmd)
  let s:list = s:GetLogList(logs)

  call s:UpdateGitLog(a:input)
endfunction

function! s:UpdateLog(input)
  let input_changed = a:input != s:input
  let prev_list = project#GetVariable('list')
  let init = empty(a:input) || empty(prev_list)
  let should_reload = input_changed || init
  if should_reload
    let list = s:FilterLogs(s:list, a:input)
    call project#SetVariable('list', list)
    let display = s:GetLogsDisplay(list, a:input)

    let s:input = a:input
    let s:display = display
  else
    let display = s:display
  endif

  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  if should_reload
    call project#HighlightInputChars(a:input)
  endif
endfunction

function! s:UpdateGitLog(input)
  call s:UpdateLog(a:input)

  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  let changed_files = s:GetChangedFiles(revision)
  if !empty(changed_files)
    call popup_clear()
    let title = revision.message
    let changed_files = [title, ''] + changed_files
    call popup_notification(changed_files, 
       \ #{ line: 1, col: 999, pos: 'topright', highlight: 'Normal',
       \ time: 1, minwidth: &columns / 2, maxwidth: &columns - 20 })
  endif
endfunction

function! s:OpenGitLog(revision, cmd, input)
  call s:OpenChangesBuffer()
  call s:SetupChangesBuffer(a:revision)
  call s:AddToBuffer(a:revision)
endfunction

function! s:CloseGitLog()
  let s:list = []
  let s:display = []
endfunction

function! s:OpenBuffer(search, name, pos)
  let num = bufwinnr(escape(a:search, '[]'))
  if num == -1
    execute 'silent '.a:pos.' split '.a:name
    setlocal buftype=nofile bufhidden=wipe nobuflisted
  else
    execute num.'wincmd w'
    execute 'silent e '.a:name
    setlocal buftype=nofile bufhidden=wipe nobuflisted
  endif
endfunction

function! s:CloseBuffer(name)
  let nr = bufnr(escape(a:name, '[]'))
  if nr != -1
    execute 'silent bdelete '.nr
  endif
endfunction

function! s:OpenChangesBuffer()
  call s:OpenBuffer(s:changes_buffer, s:changes_buffer, 'botright')
endfunction

function! s:CloseChangesBuffer()
  call s:CloseBuffer(s:changes_buffer)
  call s:CloseBuffer('[Before]')
  call s:CloseBuffer('[After]')
endfunction

function! s:SetupChangesBuffer(revision)
  hi DiffBufferModify ctermfg=3 guifg=#b58900
  hi DiffBufferAdd ctermfg=2 guifg=#719e07
  hi DiffBufferDelete ctermfg=9 guifg=#dc322f
  syntax match DiffBufferModify /^M\ze\s/
  syntax match DiffBufferAdd /^A\ze\s/
  syntax match DiffBufferDelete /^D\ze\s/

  execute "nnoremap <buffer> <cr> :call <SID>ShowDiff('".a:revision.hash."')<cr>"
endfunction

function! s:ShowDiff(hash)
  let line = getline('.')
  let file = matchstr(line, '^\S\s\zs.*')
  if empty(file)
    return 
  endif
  
  let filename = fnamemodify(file, ':t')
  call s:OpenBuffer('[Before] ', '[Before] '.filename, 'botright')
  let content = systemlist('git show '.a:hash.'~:'.file)
  if !v:shell_error
    call append(0, content)
    nnoremap <buffer> <c-n> ]c
    nnoremap <buffer> <c-p> [c
  endif
  diffthis

  call s:OpenBuffer('[After] ', '[After] '.filename, 'vertical')
  let content = systemlist('git show '.a:hash.':'.file)
  if !v:shell_error
    call append(0, content)
    nnoremap <buffer> <c-n> ]c
    nnoremap <buffer> <c-p> [c
  endif
  diffthis
  normal! gg
endfunction

function! s:GetChangedFiles(revision)
  let cmd = 'git diff-tree --no-commit-id --name-status -r -m --root '.a:revision.hash
  let changed_files = map(systemlist(cmd), 'substitute(v:val, "\t", " ", "")')
  if v:shell_error
    return []
  else
    return changed_files
  endif
endfunction

function! s:AddToBuffer(revision)
  let changed_files = s:GetChangedFiles(a:revision)

  setlocal modifiable
  normal! gg"_dG
  if len(changed_files) > 0
    call append(0, changed_files)
  else
    call append(0, 'No files found')
  endif

  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)

  setlocal nomodifiable
  normal! gg
endfunction

function! s:GenerateBrief(revision)
  let brief = []
  call add(brief, a:revision.message)
  call add(brief, '')
  call add(brief, a:revision.hash.' by '.a:revision.author.' <'.a:revision.email.'> '
    \.a:revision.date)
  return brief
endfunction

function! s:GetLogList(logs)
  let list = []
  for log in a:logs
    let [message, author, email, date, hash] = split(log, ' ||| ', 1)
    call insert(list, { 'message': message, 'author': author, 'date': date, 'hash': hash, 'email': email })
  endfor

  let max_col_width = &columns * 3 / 5
  call project#TabulateFixed(list, ['message', 'author', 'date'], [max_col_width, 20, 20])
  return list
endfunction

function! s:GetFileHistoryList(logs)
  let list = []
  for log in a:logs
    let [message, author, email, date, hash] = split(log, ' ||| ', 1)
    call insert(list, { 'message': message, 'author': author, 'date': date, 'hash': hash, 'email': email })
  endfor

  let max_col_width = &columns * 3 / 5
  call project#TabulateFixed(list, ['message', 'author', 'date'], [&columns/2 - 30, 10, 10])
  return list
endfunction


function! s:FilterLogs(list, input)
  let list = copy(a:list)
  if !empty(a:input)
    let pattern = s:GetRegexpFilter(a:input)
    let list = filter(list, { idx, val -> 
      \s:Match(val.message, pattern)
      \|| s:Match(val.author, pattern)
      \|| s:Match(val.hash, pattern)
      \|| (a:input[0] =~ '\d' && s:Match(val.date, pattern))
      \})
  endif
  return list
endfunction

function! s:Match(string, pattern)
  return match(a:string, a:pattern) != -1
endfunction

function! s:Include(string, substrings)
  for substr in a:substrings
    if stridx(a:string, substr) != -1
      return 1
    endif
  endfor

  return 0
endfunction

function! s:GetRegexpFilter(input)
  return join(split(a:input, ' '), '.*')
endfunction

function! s:GetLogsDisplay(list, input)
  let display = map(copy(a:list), function('s:GetLogsDisplayRow'))
  return display
endfunction

function! s:GetLogsDisplayRow(idx, value)
  if project#GetVariable('list_type') == 'GIT_FILE_HISTORY'
    return a:value.__message.' '.a:value.__author.' '.a:value.__date
  endif

  return a:value.__message.' '.a:value.__author.' '.a:value.__date.' '.a:value.hash
endfunction
