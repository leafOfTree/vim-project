let s:list = []
let s:input = ''
let s:display = []
let s:changes_buffer = 'Changes [Press Enter to view diff or take action]'

function! project#git#log()
  call project#PrepareListBuffer('Search log:', 'GIT_LOG')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let format = "%s ||| %aN ||| %ae ||| %ad ||| %h"
  let cmd = "git log --pretty=format:'".format."' --date=relative"
  let logs = project#RunShellCmd(cmd)
  let s:list = s:GetLogList(logs)

  call s:Update(a:input)
endfunction

function! s:Update(input)
  let input_changed = a:input != s:input
  let init = empty(a:input)
  if input_changed || init
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
  if input_changed
    call project#HighlightInputChars(a:input)
  endif

  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  let changed_files = s:GetChangedFiles(revision)
  if !empty(changed_files)
    call popup_clear()
    call popup_notification(changed_files, 
       \ #{ line: 1, col: 999, pos: 'topright', highlight: 'Normal',
       \ time: 1, minwidth: 40, maxwidth: &columns - 20 })
  endif
endfunction

function! s:Open(revision, cmd, input)
  call s:OpenChangesBuffer()
  call s:SetupChangesBuffer(a:revision)
  call s:AddToBuffer(a:revision)
endfunction

function! s:OpenBuffer(search, name, pos)
  let num = bufwinnr(a:search)
  if num == -1
    execute 'silent '.a:pos.' split '.a:name
    setlocal buftype=nofile bufhidden=wipe nobuflisted
  else
    execute num.'wincmd w'
    execute 'silent e '.a:name
    setlocal buftype=nofile bufhidden=wipe nobuflisted
  endif
endfunction

function! s:OpenChangesBuffer()
  call s:OpenBuffer(s:changes_buffer, s:changes_buffer, 'botright')
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
  call s:OpenBuffer('Before ', 'Before '.filename, 'leftabove')
  let content = systemlist('git show '.a:hash.'~:'.file)
  if !v:shell_error
    call append(0, content)
    nnoremap <buffer> <c-n> ]c
    nnoremap <buffer> <c-p> [c
  endif
  diffthis

  call s:OpenBuffer('After ', 'After '.filename, 'vertical')
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
  return a:value.__message.' '.a:value.__author.' '.a:value.__date.' '.a:value.hash
  " return a:value.message.' '.a:value.author.' '.a:value.date.' '.a:value.hash
endfunction
