let s:list = []
let s:display = []
let s:input = ''
let s:current_file = ''
let s:current_line = 0

let s:changes_buffer = '[changes]'
let s:changes_buffer_search = '[changes'
let s:diff_buffer = '[diff]'
let s:diff_buffer_search = '[diff'
let s:before_buffer = '[before]'
let s:before_buffer_search = '[before'
let s:after_buffer = '[after]'
let s:after_buffer_search = '[after'
let s:changelist_buffer = '[Local Changes]'
let s:changelist_buffer_search = '[Local Changes'
let s:file_history_range = []
let s:log_splitter = ' ||| '
let s:commit_diffs = []

let s:default_folder_name = 'Default'
let s:untracked_folder_name = 'Untracked'
let s:changed_files = []
let s:untracked_files = []
let s:commit_files = []
let s:file_regexp = '^\s\+\S\s\+\zs.*'
let s:folder_regexp = '^\S\s\zs.\+\ze\s\($\|\d\+\sfile\)'
let s:changelist_default = [
      \{
      \ 'name': s:default_folder_name,
      \ 'files': [],
      \ 'expand': 1,
      \},
      \{
      \ 'name': s:untracked_folder_name,
      \ 'files': [],
      \ 'expand': 0,
      \},
    \]


function! project#git#FileHistory(...)
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:CloseFileHistory()

  let s:current_file = expand('%:p')
  let filename = expand('%:t')
  if !filereadable(s:current_file)
    call project#Warn('Open a file first to show its history')
    return
  endif

  let range = a:000[0]
  let prompt = 'History of '.filename.':' 
  let s:file_history_range = []
  if range > 0
    let s:file_history_range = [line("'<"), line("'>")]
    let prompt = 'History of '.filename.' L'.join(s:file_history_range, ',').':' 
  endif

  call project#SetVariable('initial_height', winheight(0) - 5)
  call project#PrepareListBuffer(prompt, 'GIT_FILE_HISTORY')
  let Init = function('s:InitFileHistory')
  let Update = function('s:UpdateFileHistory')
  let Open = function('s:OpenFileHistory')
  let Close = function('s:CloseFileHistory')
  call project#RenderList(Init, Update, Open, Close)
endfunction

function! s:InitFileHistory(input)
  let range = s:GetLineRange()
  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:log_splitter)
  let cmd = 'git log --pretty=format:"'.format.'" --date=relative '.range.s:current_file
  let logs = project#RunShellCmd(cmd)
  if empty(range)
    let s:commit_diffs = []
  else
    let [logs, s:commit_diffs] = s:SaveCommitDiff(logs)
  endif
  let s:list = s:GetTabulatedList(logs)

  call s:UpdateFileHistory(a:input)
endfunction

function! s:SaveCommitDiff(logs)
  let logs = []
  let commit_diffs = {}

  let hash = ''
  for log in a:logs
    if match(log, s:log_splitter) != -1
      call add(logs, log)
      let hash = split(log, s:log_splitter, 1)[-1]
      let commit_diffs[hash] = []
    else
      call add(commit_diffs[hash], log)
    endif
  endfor

  return [logs, commit_diffs]
endfunction

function! s:GetLineRange()
  let range = ''
  if !empty(s:file_history_range)
    let [firstline, lastline] = s:file_history_range
    let range = ' -L'.firstline.','.lastline.':'
  endif
  return range
endfunction

function! s:UpdateFileHistory(input)
  call s:UpdateLog(a:input)
  call s:ShowDiffOfCurrentFile()
endfunction

function! s:ShowDiffOfCurrentFile()
  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:AddDiffDetails(revision.hash, s:current_file)
  call s:AddBrief(revision)
  call s:SetupDiffBuffer()
  wincmd h
endfunction

function! s:AddDiffDetails(hash, file)
  let changes = []
  let is_diff_on_range = !empty(s:commit_diffs)
  if is_diff_on_range
    let changes = s:commit_diffs[a:hash]
  else
    let cmd = 'git show --pretty=format:"" '.a:hash.' '.a:file
    let changes = project#RunShellCmd(cmd)
  endif

  call append(0, changes)
  normal! gg
  silent! g/^new file mode/d

  if is_diff_on_range
    silent! 1,3d
  else
    silent! 1,4d
  endif
endfunction

function! s:AddBrief(revision)
  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)
endfunction

function! s:SetupDiffBuffer()
  setlocal buftype=nofile bufhidden=wipe nobuflisted filetype=git
  setlocal nowrap
endfunction

function! s:OpenFileHistory(revision, cmd, input)
  " just keep [diff] window
endfunction

function! s:CloseFileHistory()
  call s:CloseBuffer(s:diff_buffer_search)
endfunction

function! project#git#Log()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:CloseChangesBuffer()

  call project#SetVariable('initial_height', winheight(0) - 5)
  call project#PrepareListBuffer('Search log:', 'GIT_LOG')
  let Init = function('s:InitGitLog')
  let Update = function('s:UpdateGitLog')
  let Open = function('s:OpenGitLog')
  let Close = function('s:CloseGitLog')
  call project#RenderList(Init, Update, Open, Close)
endfunction


function! s:InitGitLog(input)
  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:log_splitter)
  let cmd = 'git log --pretty=format:"'.format.'" --date=relative'
  let logs = project#RunShellCmd(cmd)
  let s:list = s:GetTabulatedList(logs)

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
  call s:ShowCurrentChangdFiles()
endfunction

function! s:ShowCurrentChangdFiles()
  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  let changed_files = s:GetChangedFiles(revision)
  if empty(changed_files)
    return
  endif

  call s:OpenBuffer(s:changes_buffer_search, s:changes_buffer, 'vertical')
  call s:SetupChangesBuffer(revision)
  call s:AddToBuffer(revision)
  wincmd h
endfunction


function! s:OpenGitLog(revision, cmd, input)
  execute 'autocmd CursorMoved <buffer> call s:ShowDiffOnGitLog("'.a:revision.hash.'")'
endfunction

function! s:CloseGitLog()
  let s:list = []
  let s:display = []
  call s:CloseChangesBuffer()
endfunction

function! s:OpenBuffer(search, name, pos)
  let num = s:GetBufWinnr(a:search)
  if num == -1
    execute 'silent '.a:pos.' new '.a:name
  else
    execute num.'wincmd w'
    execute 'silent e '.a:name
  endif
  setlocal buftype=nofile bufhidden=wipe nobuflisted
endfunction

function! s:SwitchBuffer(search)
  let num = s:GetBufWinnr(a:search)
  if num != -1
    execute num.'wincmd w'
  endif
endfunction

function! s:GetBufWinnr(search)
  return bufwinnr(escape(a:search, '[]'))
endfunction

function! s:GetBufnr(search)
  return bufnr(escape(a:search, '[]'))
endfunction

function! s:CloseBuffer(name)
  if bufname() == a:name
    quit
    return
  endif

  let nr = s:GetBufnr(a:name)
  if nr != -1
    execute 'silent! bdelete '.nr
    if empty(bufname())
      quit
    endif
  endif
endfunction

function! s:CloseChangesBuffer()
  call s:CloseBuffer(s:changes_buffer_search)
  call s:CloseBuffer(s:before_buffer_search)
  call s:CloseBuffer(s:after_buffer_search)
  call s:CloseBuffer(s:diff_buffer_search)
endfunction

function! s:SetupChangesBuffer(revision)
  hi DiffBufferModify ctermfg=3 guifg=#b58900
  hi DiffBufferAdd ctermfg=2 guifg=#719e07
  hi DiffBufferDelete ctermfg=9 guifg=#dc322f
  syntax match DiffBufferModify /^M\ze\s/
  syntax match DiffBufferAdd /^A\ze\s/
  syntax match DiffBufferDelete /^D\ze\s/

  setlocal buftype=nofile bufhidden=wipe nobuflisted
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
endfunction

function! s:ShowDiffOnChangelist()
  if mode() != 'n'
    return
  endif
  let lnum = line('.')
  let is_first_line = lnum == 1
  let no_moving = lnum == s:current_line
  if is_first_line || no_moving
    return 
  endif
  let file = s:GetCurrentFile(lnum)
  let num = s:GetBufWinnr(s:diff_buffer_search)
  if empty(file) && num == -1
    return
  endif

  let s:current_line = lnum
  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:SetupDiffBuffer()
  wincmd h

  if empty(file)
    return
  endif
  call s:AddChangeDetails(file)
endfunction

function! s:AddChangeDetails(file)
  if s:IsUntrackedFile(a:file)
    let cmd = 'git diff --no-index -- /dev/null '.a:file.''
  else
    let cmd = 'git diff -- '.a:file
  endif
  let buf_nr = s:GetBufnr(s:diff_buffer_search)
  call s:RunJob(cmd, 'VimProjectAddChangeDetails', buf_nr)
endfunction

function! s:IsUntrackedFile(file)
  for untracked_file in s:untracked_files
    if s:GetFilename(untracked_file) == a:file
      return 1
    endif
  endfor
  return 0
endfunction

function! s:RunJob(cmd, exit_cb, buf_nr)
  let can_run = exists('*job_start') || exists('*jobstart')
  if !can_run
    return
  endif

  " vim
  if exists('*job_start')
    call job_start(a:cmd, { 
          \'exit_cb': a:exit_cb,
          \'out_io': 'buffer',
          \'out_buf': a:buf_nr,
          \'cwd': $vim_project,
          \})
  endif
  " neovim
  if exists("*jobstart")
    call jobstart(a:cmd, {
        \'on_stdout': a:exit_cb,
        \'stdout_buffered': 1,
        \})
  endif
endfunction

function! VimProjectAddChangeDetails(job, exit_status, ...)
  call s:SwitchBuffer(s:diff_buffer_search)

  silent! g/^new file mode/d
  silent! 1,4d
  normal! gg
  call s:SwitchBuffer(s:changelist_buffer_search)
endfunction

function! s:AddChangeDetailsOld(file)
  let cmd = 'git diff -- '.a:file
  let changes = project#RunShellCmd(cmd)
  if empty(changes)
    " For untracked files
    " Have to add ' || true' as 'git diff --no-index' returns 0 for no changes, 1 changes
    let cmd = 'git diff --no-index -- /dev/null '.a:file.' || true'
    let changes = project#RunShellCmd(cmd)
  endif

  call append(0, changes)
  normal! gg
  silent! g/^new file mode/d
  silent! 1,4d
endfunction

function! s:ShowDiffOnGitLog(hash)
  if mode() != 'n'
    return
  endif

  let line = getline('.')
  let file = matchstr(line, '^\S\s\zs.*')
  if empty(file)
    return
  endif

  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:AddDiffDetails(a:hash, file)
  call s:SetupDiffBuffer()
  wincmd h
endfunction

function! s:ShowDiffSideBySide(hash)
  let line = getline('.')
  let file = matchstr(line, '^\S\s\zs.*')
  if empty(file)
    return 
  endif
  
  let filename = fnamemodify(file, ':t')
  call s:OpenBuffer(s:before_buffer_search, s:before_buffer.' '.filename, 'botright')
  let content = systemlist('git show '.a:hash.'~:'.file)
  if !v:shell_error
    call append(0, content)
    nnoremap <buffer> <c-n> ]c
    nnoremap <buffer> <c-p> [c
  endif
  diffthis

  call s:OpenBuffer(s:after_buffer_search, s:after_buffer.' '.filename, 'vertical')
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
  let changed_files = map(project#RunShellCmd(cmd), 'substitute(v:val, "\t", " ", "")')
  if v:shell_error
    return []
  else
    return changed_files
  endif
endfunction

function! s:AddToBuffer(revision)
  let changed_files = s:GetChangedFiles(a:revision)

  if len(changed_files) > 0
    call append(0, changed_files)
  else
    call append(0, 'No files found')
  endif

  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)
  normal! gg
endfunction

function! s:GenerateBrief(revision)
  let brief = []
  call add(brief, '----------------------------------------------------------------------------')
  call add(brief, a:revision.message)
  call add(brief, '')
  call add(brief, a:revision.hash.' by '.a:revision.author.' <'.a:revision.email.'> '
    \.a:revision.date)
  return brief
endfunction

function! s:GetTabulatedList(logs)
  let list = []
  for log in a:logs
    let [message, author, email, date, hash] = split(log, s:log_splitter, 1)
    let date = s:ShortenDate(date)
    call insert(list, 
          \{ 'message': message, 'author': author, 'date': date, 'hash': hash, 'email': email })
  endfor

  call project#TabulateFixed(list, ['message', 'author', 'date'], [&columns/2 - 30, 10, 10])
  return list
endfunction

function! s:ShortenDate(origin)
  let date = substitute(a:origin, 'years\?', 'y', 'g')
  let date = substitute(date, 'months\?', 'm', 'g')
  let date = substitute(date, 'weeks\?', 'w', 'g')
  let date = substitute(date, 'days\?', 'd', 'g')
  return date
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
  return a:value.__message.' '.a:value.__author.' '.a:value.__date
endfunction

function! project#git#Status()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  " Manually trigger some events first
  silent doautocmd BufLeave
  silent doautocmd FocusLost
  call s:LoadChangelist()
  call s:ShowStatus(1)
endfunction

function! project#git#push()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:TryPush()
endfunction

function! project#git#pull()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:TryPull()
endfunction

function! s:GetChangelistFile()
  return $vim_project_config.'/changelist.txt'
endfunction

function! s:ReadChangelistFile()
  try 
    let changelist_string = readfile(s:GetChangelistFile())
    if !empty(changelist_string) && len(changelist_string) == 1
      return json_decode(changelist_string[0])
    endif
  catch
  endtry
endfunction

function! s:WriteChangelistFile()
  let changelist_string = json_encode(s:changelist)
  call writefile([changelist_string], s:GetChangelistFile())
endfunction

function! s:LoadChangelist()
  let changelist = s:ReadChangelistFile()
  if !empty(changelist)
    let s:changelist = changelist
  else
    let s:changelist = s:changelist_default
  endif
endfunction

function! s:SortChangelist()
  call sort(s:changelist, 's:SortChangelistFunc')
endfunction

function! s:SortChangelistFunc(i1, i2)
  if a:i1.name == s:default_folder_name || a:i2.name == s:untracked_folder_name
    return -1
  endif
  if a:i1.name == s:untracked_folder_name || a:i2.name == s:default_folder_name
    return 1
  endif

  return a:i1.name > a:i2.name ? 1 : -1
endfunction

function! s:ToggleFolderOrOpenFile()
  let lnum = line('.')
  let item = s:GetCurrentFolder(lnum)
  if !empty(item)
    let item.expand = 1 - item.expand
    call s:ShowStatus()
    execute lnum
  else
    let file = s:GetCurrentFile(lnum)
    if !empty(file)
      wincmd k
      execute 'e '.$vim_project.'/'.file
    endif
  endif
endfunction

function! s:RenameFolderOrRollbackFile()
  let lnum = line('.')
  let item = s:GetCurrentFolder(lnum)
  if !empty(item)
    if s:IsUserFolder(item)
      let name = input('Rename to: ', item.name)
      if !empty(name)
        if empty(s:GetChangelistItem(name))
          let item.name = name
          call s:SortChangelist()
          call s:ShowStatus()
          call search(name)
        else
          call project#Warn('Changelist '.name.' exists')
        endif
      endif
    endif
  else
    let file = s:GetCurrentFile(lnum)
    let name = input('Rollback changes of '.file.'? (y/n) ')
    if !empty(name)
      let cmd = 'git restore -- '.file
      call project#RunShellCmd(cmd)
      call s:ShowStatus(1)
    endif
  endif
endfunction

function! s:IsUserFolder(item)
  return !empty(a:item) 
        \&& a:item.name != s:default_folder_name && a:item.name != s:untracked_folder_name
endfunction

function! s:DeleteFolder()
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)
  if s:IsUserFolder(folder)
    call remove(s:changelist, index(s:changelist, folder))
  endif
  call s:ShowStatus()
  execute lnum
endfunction

function! VimProjectAllFolderNames(A, L, P)
  let lnum = line('.')
  let folder = s:GetBelongFolder(lnum)

  let folder_names = map(copy(s:changelist), {idx, v -> v.name})
  call filter(folder_names, {idx, v -> 
        \v != s:untracked_folder_name 
        \&& v != folder.name
        \&& v =~ a:A
        \})
  return folder_names
endfunction

function! s:MoveToChangelist() range
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)

  if !empty(folder)
    let name = input('Move to: ', '', 'customlist,VimProjectAllFolderNames')
    if empty(name)
      return
    endif

    call s:MoveFolderTo(folder, name)
  else
    let file = s:GetCurrentFile(lnum)
    if !empty(file)
      let name = input('Move to: ', '', 'customlist,VimProjectAllFolderNames')
      if empty(name)
        return
      endif

      for lnum in range(a:firstline, a:lastline)
        call s:MoveFileTo(lnum, name)
      endfor
    else
      return
    endif
  endif

  call s:ShowStatus()
  if !empty(name)
    call search(name)
  endif
endfunction

function! s:MoveFolderTo(from_folder, to_name)
  let files = a:from_folder.files
  let a:from_folder.files = []
  let target = s:GetChangelistItem(a:to_name)
  if empty(target)
    call s:AddNewFolder(a:to_name, files)
  else
    call extend(target.files, files)
    let target.expand = 1
  endif
endfunction

function! s:MoveFileTo(from_lnum, to_name) 
  let cur_line = getline(a:from_lnum)
  if cur_line !~ s:file_regexp
    return
  endif

  let file = matchstr(cur_line, s:file_regexp)
  let from_folder = s:GetBelongFolder(a:from_lnum)
  call filter(from_folder.files, 'v:val != "'.file.'"')

  let target = s:GetChangelistItem(a:to_name)
  if empty(target)
    call s:AddNewFolder(a:to_name, [file])
  else
    call add(target.files, file)
    let target.expand = 1
  endif
endfunction

function! s:AddNewFolder(name, files)
  let target = {
        \ 'name': a:name,
        \ 'files': a:files,
        \ 'expand': 1,
        \}
  call add(s:changelist, target)
  call s:SortChangelist()
endfunction

function! s:GetCurrentFile(lnum)
  return matchstr(getline(a:lnum), s:file_regexp)
endfunction

function! s:GetBelongFolder(lnum)
  let lnum = a:lnum
  while getline(lnum) !~ s:folder_regexp && lnum > -1
    let lnum = lnum - 1
  endwhile
  return s:GetCurrentFolder(lnum)
endfunction

function! s:GetCurrentFolder(lnum)
  let prev_line = getline(a:lnum - 1)
  if prev_line =~ '^\s*$'
    let cur_line = getline(a:lnum)
    let list_name = matchstr(cur_line, s:folder_regexp)
    return s:GetChangelistItem(list_name)
  endif
endfunction

function! s:GetChangelistItem(name)
  for item in s:changelist
    if item.name == a:name
      return item
    endif
  endfor
endfunction

function! s:GetFilename(file)
  return split(a:file, '\s\+')[-1]
endfunction

function! s:GetPrefixAndSuffix(folder)
  let expand = '▼'
  let collapse = '▶'
  let empty = '-'

  let prefix = a:folder.expand ? expand : collapse
  let suffix = ''

  let file_num = 0
  for file in (s:changed_files + s:untracked_files)
    if s:HasFile(a:folder.files, file)
      let file_num += 1
    endif
  endfor

  if !file_num
    let prefix = empty
  elseif file_num == 1
    let suffix = file_num.' file'
  else
    let suffix = file_num.' files'
  endif

  return [prefix, suffix]
endfunction

function! s:AddUntrackedPrefix(files)
  return map(copy(a:files), {idx, file -> 'U '.file})
endfunction

function! s:UpdatePresetChangelist()
  for file in s:changed_files
    let in_default = 1
    for folder in s:changelist
      if s:HasFile(folder.files, file)
        let in_default = 0
      endif
    endfor

    if in_default
      call add(s:changelist[0].files, s:GetFilename(file))
    endif
  endfor

  let s:changelist[-1].files = []
  for file in s:untracked_files
    let in_untracked = 1
    for folder in s:changelist
      if s:HasFile(folder.files, file)
        let in_untracked = 0
      endif
    endfor

    if in_untracked
      call add(s:changelist[-1].files, s:GetFilename(file))
    endif
  endfor
endfunction

function! s:UpdateChangelistDisplay()
  let s:display = []
  for folder in s:changelist
    if s:IsUntrackedFolder(folder) && empty(folder.files)
      continue
    endif
    let [prefix, suffix] = s:GetPrefixAndSuffix(folder)
    call add(s:display, prefix.' '.folder.name.' '.suffix)
    if folder.expand
      for file in (s:changed_files + s:untracked_files)
        if s:HasFile(folder.files, file)
          call add(s:display, '  '.file)
        endif
      endfor
    endif
    call add(s:display, '')
  endfor
endfunction

function! s:UpdateChangelist(run_git = 0)
  if a:run_git
    let s:changed_files = project#RunShellCmd('git diff --name-status')
    if !empty(s:changed_files) && s:changed_files[0] =~ 'Not a git repository'
      return 0
    endif
    let s:untracked_files = s:AddUntrackedPrefix(
      \project#RunShellCmd('git ls-files --exclude-standard --others'))
  endif

  call s:UpdatePresetChangelist()
  call s:UpdateChangelistDisplay()
  return 1
endfunction

function! s:IsUntrackedFolder(folder)
  return a:folder.name == s:untracked_folder_name
endfunction

function! s:HasFile(files, file)
  let filename = s:GetFilename(a:file)
  return count(a:files, filename)
endfunction

function! s:ShowStatus(run_git = 0)
  " Ignore events to avoid a cursor bug when opening from Fern.vim
  let save_eventignore = &eventignore
  set eventignore=all

  call s:OpenBuffer(s:changelist_buffer_search, s:changelist_buffer, 'belowright')
  call s:SetupChangelistBuffer()
  let success = s:UpdateChangelist(a:run_git)
  if success
    call s:WriteChangelist()
  endif

  let &eventignore = save_eventignore
endfunction

function! s:SetupChangelistBuffer()
  nnoremap<buffer><silent> o :call <SID>ToggleFolderOrOpenFile()<cr>
  nnoremap<buffer><silent> r :call <SID>RenameFolderOrRollbackFile()<cr>
  nnoremap<buffer><silent> d :call <SID>DeleteFolder()<cr>
  nnoremap<buffer><silent> c :call <SID>Commit()<cr>
  nnoremap<buffer><silent> u :call <SID>TryPull()<cr>
  nnoremap<buffer><silent> p :call <SID>TryPush()<cr>

  noremap<buffer><silent> m :call <SID>MoveToChangelist()<cr>

  syntax match Comment /\d\+ files\?/
  setlocal buftype=nofile
  setlocal nomodifiable
  execute 'syntax match Keyword /'.s:folder_regexp.'/'
  autocmd CursorMoved <buffer> call s:ShowDiffOnChangelist()
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
  autocmd BufUnload <buffer> call s:WriteChangelistFile()
  let s:current_line = 0
endfunction

function! s:WriteChangelist()
  setlocal modifiable
  call execute('normal! ggdG', 'silent!')
  call append(0, s:display)
  normal gg
  setlocal nomodifiable
endfunction

function! s:Commit()
  let files = []

  let lnum = line('.')
  if getline(lnum) =~ '^\s*$'
    return
  endif

  let file = s:GetCurrentFile(lnum)
  if empty(file)
    let folder = s:GetBelongFolder(lnum)
    let files = folder.files
  else
    let files = [file]
  endif

  let check_files = s:changed_files + s:untracked_files
  let commit_files = filter(check_files, {idx, file -> s:HasFile(files, file)}) 
  if empty(commit_files)
    return 
  endif
  let s:commit_files = map(copy(commit_files), {idx, file -> s:GetFilename(file)})
  let show_commit_files = map(copy(commit_files), {idx, file -> '#    '.file})

  let title = s:GetCommitMessage()
  quit
  call s:ShowCommitMessage(title, show_commit_files)
endfunction

function! s:GetCommitMessage()
  let folder_name = ''

  let lnum = line('.')
  let folder = s:GetBelongFolder(lnum)
  let folder_name = !empty(folder) ? folder.name : ''

  let title = ''
  let Message = project#GetVariable('commit_message')

  if !empty(Message)
    if type(Message) == type(function('tr'))
      let title = Message(folder_name)
    elseif type(Message) == type('')
      let title = Message
    endif
  endif

  if empty(title) && s:IsUserFolder(folder)
    let title = folder_name
  endif
  return title
endfunction

function! s:ShowCommitMessage(title, files)
  let preset_message = [
        \'# Please enter the commit message for your changes. Lines starting',
        \"# with '#' will be ignored, and an empty message aborts the commit.",
        \'#',
        \'# On branch master',
        \'# Changes to be committed:'
        \]
  new COMMIT_EDITMSG
  let content = [a:title] + preset_message + a:files
  call append(0, content)
  set filetype=gitcommit
  setlocal buftype=nofile
  normal! gg
  syntax match Normal /#\s\{4}\zs.*/ containedin=gitcommitSelected
  autocmd WinClosed <buffer> ++once  call s:TryCommit()
endfunction

function! s:TryCommit()
  let lines = getline(0, line('$'))
  let message_lines = filter(lines, {idx, val -> val =~ '^[^#]' && val !~ '^\s*$' && val !~ '^amend$'})
  let lines = getline(0, line('$'))
  let amend_lines = filter(lines, {idx, val -> val =~ '^amend$'})
  let is_empty_message = empty(message_lines)
  let is_amend = !empty(amend_lines)
  if is_empty_message && !is_amend
    call project#Info('Commit canceled')
    return
  endif

  let files = join(s:commit_files, ' ')
  let message = join(map(message_lines, {idx, val -> '-m "'.escape(val, '"').'"'}), ' ')

  let option = ''
  if is_amend
    let option = option.' --amend --no-edit'
  endif

  let cmd = 'git add '.files.' && git commit '.message.option
  let result = project#RunShellCmd(cmd)

  quit
  call s:OpenResultWindow('COMMIT_RESULT', cmd, result)
  nnoremap<buffer><silent> u :call <SID>TryPull()<cr>
  nnoremap<buffer><silent> p :call <SID>TryPush()<cr>
endfunction

function! s:TryPush()
  call project#Info('Pushing...')
  let cmd = 'git push'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  redraw
  call project#Info('Pushed sucessfully')
endfunction

function! s:TryPull()
  call project#Info('Updating...') 
  let cmd = 'git pull'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  redraw
  call project#Info('Updated sucessfully')
endfunction

function! s:ShowResultMessage(result)
  redraw
  if len(a:result) < 3
    call project#Info(join(a:result, ' | '))
  else
    for line in a:result
      call project#Info(line)
    endfor
  endif
endfunction

function! s:OpenResultWindow(title, cmd, result)
  execute 'new '.a:title
  call append(0, [a:cmd, ''] + a:result)
  setlocal buftype=nofile
  normal! gg
endfunction
