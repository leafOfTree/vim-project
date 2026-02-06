let s:list = []
let s:display = []
let s:input = ''
let s:current_file = ''
let s:current_line = 0

let s:changes_buffer = 'changes'
let s:diff_buffer = 'diff'
let s:before_buffer = 'before'
let s:after_buffer = 'after'
let s:changelist_buffer = 'local_changes'
let s:commit_edit_buffer = 'commit_editmsg'
let s:commit_result_buffer = 'commit_result'
let s:file_history_range = []
let s:splitter = ' ||| '
let s:commit_diffs = []

let s:default_folder_name = 'Default'
let s:untracked_folder_name = 'Untracked'
let s:staged_folder_name = 'Staged'
let s:unmerged_folder_name = 'Unmerged'

let s:shelf_folder_prefix = '📚'
let s:shelf_path_spliter = '#'
let s:shelf_path_file_spliter = '@'

let s:changed_files = []
let s:untracked_files = []
let s:staged_files = []
let s:unmerged_files = []
let s:commit_files = []
let s:file_regexp = '|\zs.*\ze|'
let s:directory_regexp = '| \zs.*$'
let s:folder_regexp = '^\S\s.*|\zs.\+\ze\s\($\|\d\+\sfile\)'
let s:changelist_default = [
      \{
      \ 'name': s:default_folder_name,
      \ 'files': [],
      \ 'expand': 1,
      \},
      \{
      \ 'name': s:unmerged_folder_name,
      \ 'files': [],
      \ 'expand': 0,
      \},
      \{
      \ 'name': s:untracked_folder_name,
      \ 'files': [],
      \ 'expand': 0,
      \},
      \{
      \ 'name': s:staged_folder_name,
      \ 'files': [],
      \ 'expand': 0,
      \},
    \]
let s:item_splitter = '----------------------------------------------------------------------------'

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

  call project#SetVariable('initial_height', winheight(0) - 10)
  call project#PrepareListBuffer(prompt, 'GIT_FILE_HISTORY')
  let Init = function('s:InitFileHistory')
  let Update = function('s:UpdateFileHistory')
  let Open = function('s:OpenFileHistory')
  let Close = function('s:CloseFileHistory')
  call project#RenderList(Init, Update, Open, Close)
endfunction

function! s:InitFileHistory(input)
  let range = s:GetLineRange()
  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:splitter)
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
    if match(log, s:splitter) != -1
      call add(logs, log)
      let hash = split(log, s:splitter, 1)[-1]
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
  call s:ShowDiffOnFileHistory()
endfunction

function! s:ShowDiffOnFileHistory()
  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  call s:OpenBuffer(s:diff_buffer, 'vertical')
  call s:AddDiffDetails(revision.hash, s:current_file)
  call s:AddBrief(revision)
  call s:SetupDiffBuffer(s:current_file)
  wincmd p
endfunction

function! s:AddDiffDetails(hash, file)
  let changes = []
  let is_diff_line = !empty(s:commit_diffs) && has_key(s:commit_diffs, a:hash)
  if is_diff_line
    let changes = s:commit_diffs[a:hash]
  else
    let cmd = 'git show --first-parent --pretty=format:"" '.a:hash.' -- "'.a:file.'"'
    let changes = project#RunShellCmd(cmd)
  endif

  setlocal modifiable
  call append(0, changes)
  call s:ClearDiffHeaders()
  normal! gg
  setlocal nomodifiable
endfunction

function! s:AddBrief(revision)
  setlocal modifiable
  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)
  setlocal nomodifiable
endfunction

function! s:SetupDiffBuffer(file)
  setlocal buftype=nofile bufhidden=wipe nobuflisted filetype=git
  setlocal nowrap
  setlocal modifiable
  let mappings = project#GetVariable('git_diff_mappings')
  call s:AddMapping(mappings.jump_to_source, '<SID>JumpToSource("'.a:file.'")')
endfunction

function! s:JumpToSource(file)
  let lnum = line('.')
  let line_prev2 = s:SearchFileForLine(a:file, lnum - 2)
  let line_prev1 = s:SearchFileForLine(a:file, lnum - 1)
  let line = s:SearchFileForLine(a:file, lnum)

  wincmd t
  execute 'e '.a:file
  call search('\V'.line_prev2)
  call search('\V'.line_prev1)
  call search('\V'.line)
endfunction

function! s:SearchFileForLine(file, lnum)
  let lnum = a:lnum
  let line = getline(lnum)
  while (line =~ '^-' || line =~ '^.\s*$') && lnum > 0
    let lnum = lnum - 1
    let line = getline(lnum)
  endwhile
  let line = substitute(line, '^@@.*@@', '', 'g')
  let line = substitute(line, '^ *', '', 'g')
  let line = substitute(line, '^+\{1,}', '', 'g')
  let line = escape(line, '\')
  return line
endfunction

function! s:OpenFileHistory(revision, cmd, input)
  " just keep [diff] window
endfunction

function! s:CloseFileHistory()
  call s:CloseBuffer(s:diff_buffer)
endfunction

function! project#git#Log()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  call s:CloseChangesBuffer()

  call project#SetVariable('initial_height', winheight(0) - 10)
  call project#PrepareListBuffer('Search log:', 'GIT_LOG')
  let Init = function('s:InitGitLog')
  let Update = function('s:UpdateGitLog')
  let Open = function('s:OpenGitLog')
  let Close = function('s:CloseGitLog')
  call project#RenderList(Init, Update, Open, Close)
endfunction


function! s:InitGitLog(input)
  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:splitter)
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
    call project#HighlightNoResults()
  endif
endfunction

function! s:UpdateGitLog(input)
  call s:UpdateLog(a:input)
  call s:ShowCurrentChangedFiles()
endfunction

function! s:ShowCurrentChangedFiles()
  let revision = project#GetTarget()
  if empty(revision)
    return
  endif
  let changed_files = s:GetChangedFiles(revision)
  if empty(changed_files)
    return
  endif

  call s:OpenBuffer(s:changes_buffer, 'vertical')
  call s:SetupChangesBuffer(revision)
  call s:AddToBuffer(revision)
  wincmd p
endfunction


function! s:OpenGitLog(revision, cmd, input)
  if has('nvim')
    call s:ShowDiffOnGitLog(a:revision.hash)
  endif

  execute 'autocmd CursorMoved <buffer> call s:ShowDiffOnGitLog("'.a:revision.hash.'")'
endfunction

function! s:CloseGitLog()
  let s:list = []
  let s:display = []
  call s:CloseChangesBuffer()
endfunction

function! s:OpenBuffer(name, pos)
  let num = s:GetBufWinnr(a:name)
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
    return 0
  endif
  return 1
endfunction

function! s:GetBufWinnr(search)
  return bufwinnr('^'.escape(a:search, '[]').'$')
endfunction

function! s:GetBufnr(search)
  return bufnr('^'.escape(a:search, '[]').'$')
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
  call s:CloseBuffer(s:changes_buffer)
  call s:CloseBuffer(s:before_buffer)
  call s:CloseBuffer(s:after_buffer)
  call s:CloseBuffer(s:diff_buffer)
endfunction

function! s:SetupChangesBuffer(revision)
  hi DiffBufferModify ctermfg=3 guifg=#b58900
  hi DiffBufferAdd ctermfg=2 guifg=#719e07
  hi DiffBufferDelete ctermfg=9 guifg=#dc322f
  syntax match DiffBufferModify /^M\ze\s/
  syntax match DiffBufferAdd /^A\ze\s/
  syntax match DiffBufferDelete /^D\ze\s/
  syntax match Splitter "|" conceal
  syntax match Splitter "\$" conceal
  syntax match Splitter "!" conceal
  setlocal conceallevel=3 
  setlocal concealcursor=nvc

  setlocal buftype=nofile bufhidden=wipe nobuflisted
  setlocal nowrap
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
  let s:current_line = 0
  let mappings = project#GetVariable('git_changes_mappings')
  call s:AddMapping(mappings.open_file, '<SID>OpenChangedFile()')
endfunction

function! s:AddMapping(key, func)
  execute 'nnoremap<buffer><silent> '.a:key.' :call '.a:func.'<cr>'
endfunction

function! s:AddVisualMapping(key, func)
  execute 'vnoremap<buffer><silent> '.a:key.' :call '.a:func.'<cr>'
endfunction

function! s:OpenChangedFile()
  let file = s:GetCurrentFile()
  if empty(file)
    return
  endif
  wincmd k
  execute 'e '.s:GetAbsolutePath(file)
endfunction

function! s:CanShowDiff()
  if mode() != 'n'
    return 0
  endif
  let lnum = line('.')
  let no_moving = lnum == s:current_line
  let s:current_line = lnum
  if no_moving
    return 0
  endif

  let file = s:GetCurrentMatchstr(s:file_regexp)
  let num = s:GetBufWinnr(s:diff_buffer)
  if empty(file) && num == -1
    return 0
  endif

  return 1
endfunction

function! s:ShowDiffOnChangelist()
  if !s:CanShowDiff()
    return
  endif

  let file = s:GetCurrentFile()
  if empty(file)
    call s:CloseBuffer(s:diff_buffer)
    return
  endif
  " Avoid E242
  try
    call s:OpenBuffer(s:diff_buffer, 'vertical')
    call s:SetupDiffBuffer(s:GetAbsolutePath(file))
    wincmd p

    call s:AddChangeDetails(file)
  catch
    call project#Warn(v:exception)
  endtry
endfunction

function! s:GetDiffCmd(file)
  if s:IsStagedFile(a:file)
    let cmd = 'git diff --staged -- "'.a:file.'"'
  elseif s:IsUntrackedFile(a:file)
    let cmd = 'git diff --no-index -- /dev/null "'.a:file.'"'
  else
    let cmd = 'git diff -- "'.a:file.'"'
  endif
  return cmd
endfunction

function! s:AddChangeDetails(file)
  let diff_file = s:TryGetDiffFile(a:file)
  if !empty(diff_file)
    let cmd = 'cat '.diff_file
  elseif isdirectory(s:GetAbsolutePath(a:file))
    let cmd = 'ls -F '.a:file
  else
    let cmd = s:GetDiffCmd(a:file)
  endif
  let buf_nr = s:GetBufnr(s:diff_buffer)
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

function! s:IsStagedFile(file)
  let folder = s:GetBelongFolder(line('.'))
  return s:IsStagedFolder(folder)
endfunction

function! s:IsShelfFile(file)
  return s:Match(a:file, '\.\(diff\|patch\)$')
endfunction

function! s:TryGetDiffFile(file)
  if !s:IsShelfFile(a:file)
    return ''
  endif
  let diff_file = s:GetDiffFileByLine(line('.'))
  if filereadable(diff_file)
    return diff_file
  endif

  return ''
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
  " nvim
  elseif exists("*jobstart")
    call jobstart(a:cmd, {
        \'on_stdout': a:exit_cb,
        \'stdout_buffered': 1,
        \'cwd': $vim_project,
        \})
  endif
endfunction

function! s:ClearDiffHeaders()
  call project#RemoveEmptyLines()
  silent! 1,g/^new file mode/d _ | break
  silent! 1,g/^diff --git/d _ | break
  silent! 1,g/^index /d _ | break
  silent! 1,g/^--- /d _ | break
  silent! 1,g/^+++ /d _ | break
endfunction

function! VimProjectAddChangeDetails(job, data, ...)
  let error = s:SwitchBuffer(s:diff_buffer)
  if error
    return
  endif
  if &modifiable == 0
    set modifiable
    normal! ggdG
  endif

  if has('nvim')
    call append(0, a:data)
  endif

  call s:ClearDiffHeaders()
  normal! gg
  setlocal nomodifiable
  call s:SwitchBuffer(s:changelist_buffer)
endfunction

function! s:ShowDiffOnGitLog(hash)
  if !s:CanShowDiff()
    return
  endif
  let file = s:GetCurrentFile()
  call s:OpenBuffer(s:diff_buffer, 'vertical')
  call s:SetupDiffBuffer(s:GetAbsolutePath(file))
  if empty(file)
    wincmd p
    return
  endif
  call s:AddDiffDetails(a:hash, file)
  wincmd p
endfunction

function! s:GetChangedFiles(revision)
  let cmd = 'git diff-tree --no-commit-id --name-status -r -m --root '.a:revision.hash
  let changed_files = map(project#RunShellCmd(cmd), 'substitute(v:val, "\t", " ", "")')
  if v:shell_error
    return []
  else
    return map(changed_files, {idx, v -> s:GetChangedFileDisplay(v, '')})
  endif
endfunction

function! s:AddToBuffer(revision)
  setlocal modifiable
  let changed_files = s:GetChangedFiles(a:revision)
  if len(changed_files) > 0
    call append(0, changed_files)
    call s:HighlightFiles(changed_files)
  else
    call append(0, 'No files found')
  endif
  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)
  normal! gg
  setlocal nomodifiable
endfunction

function! s:GenerateBrief(revision)
  let brief = []
  call add(brief, s:item_splitter)
  call add(brief, a:revision.message)
  call add(brief, '')
  call add(brief, a:revision.hash.' by '.a:revision.author.' <'.a:revision.email.'> '
    \.a:revision.date)
  return brief
endfunction

function! s:GetTabulatedList(logs)
  let list = []
  for log in a:logs
    let [message, author, email, date, hash] = split(log, s:splitter, 1)
    let date = project#ShortenDate(date)
    call insert(list, 
          \{ 'message': message, 'author': author, 'date': date, 'hash': hash, 'email': email })
  endfor

  call project#TabulateFixed(list, ['message', 'author', 'date'], [&columns/2 - 25, 10, 15])
  return list
endfunction

function! s:FilterLogs(list, input)
  let list = copy(a:list)
  if empty(a:input)
    return list
  endif
  let pattern = s:GetRegexpFilter(a:input)
  let list = filter(list, { idx, val -> 
        \s:Match(val.message, pattern)
        \|| s:Match(val.author, pattern)
        \|| s:Match(val.hash, pattern)
        \|| (a:input[0] =~ '\d' && s:Match(val.date, pattern))
        \})
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
  if !s:OnChangelistBuffer()
    call s:LoadChangelist()
  endif
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

function! project#git#CheckoutRevision()
  let target = project#GetTarget()
  let cmd = 'git checkout '.target.hash
  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif

  call project#SetVariable('offset', 0)
  let msg = 'Checked out revision: '.target.hash.' - '.target.message
  call project#SetInfoOnCloseList(msg)
endfunction

function! project#git#MergeBranch()
  let show_current_cmd = 'git branch --show-current'
  let current = project#RunShellCmd(show_current_cmd)[0]

  let target = project#GetTarget()
  let name = target.name
  let cmd = 'git merge '.name

  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif
  call project#SetVariable('offset', 0)

  let msg = 'Merged '.name.' into '.current
  call project#SetInfoOnCloseList(msg)
endfunction

function! s:GetAbsolutePath(file)
  return $vim_project.'/'.a:file
endfunction

function! s:GetChangelistFile()
  return $vim_project_config.'/changelist.json'
endfunction

function! s:ReadChangelistFile()
  try 
    let changelist_string = readfile(s:GetChangelistFile())
    if !empty(changelist_string)
      return json_decode(join(changelist_string, ''))
    endif
  catch
  endtry
endfunction

function! s:WriteChangelistFile()
  call filter(s:changelist, {idx, v -> !s:IsShelfFolder(v) })
  let changelist_string = json_encode(s:changelist)
  let content = split(changelist_string, '\(]\|}\),\zs')
  call writefile(content, s:GetChangelistFile())
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
  if s:IsShelfFolder(a:i2) || s:IsDefaultFolder(a:i1) || s:IsSpecialFolder(a:i2)
    return -1
  endif
  if s:IsShelfFolder(a:i1) || s:IsSpecialFolder(a:i1) || s:IsDefaultFolder(a:i2)
    return 1
  endif

  return a:i1.name > a:i2.name ? 1 : -1
endfunction

function! s:OpenFolderOrFile()
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)
  if empty(folder)
    let file = s:GetCurrentFile()
    if empty(file)
      return
    endif

    let diff_file = s:TryGetDiffFile(file)
    wincmd k
    if empty(diff_file)
      execute 'e '.s:GetAbsolutePath(file)
    else
      execute 'e '.diff_file
    endif
  else
    let folder.expand = 1 - folder.expand
    call s:ShowStatus()
    execute lnum
  endif
endfunction

function! s:RenameFolder()
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)
  if empty(folder)
    return
  endif

  if s:IsUserFolder(folder)
    let name = input('Rename to: ', folder.name)
    if !empty(name)
      if empty(s:GetChangelistItem(name))
        let folder.name = name
        call s:SortChangelist()
        call s:ShowStatus()
        call search(name)
      else
        call project#Warn('Changelist '.name.' exists')
      endif
    endif
  endif
  redraw
  echo
endfunction

function! s:GetShelfFolder()
  let config_home = project#GetVariable('config_home')
  let project = project#GetVariable('project')
  let config = project#GetProjectConfigPath(config_home, project)
  return config.'/shelf'
endfunction

function! s:GetDiffFilePath(dir, filename)
  return join(a:dir, s:shelf_path_spliter).s:shelf_path_file_spliter.a:filename
endfunction

function! s:ShelfFile() range
  let files = []
  for lnum in range(a:firstline, a:lastline)
    let file = s:GetFileByLine(lnum)
    if !empty(file)
      call add(files, file)
    endif
  endfor
  if empty(files)
    return
  endif

  let prompt = 'Shelf ['.join(files, ', ').'] to: '
  let name = input(prompt, '', 'customlist,VimProjectShelfFolderNames')
  if empty(name)
    return
  endif

  let folder = s:GetShelfFolder().'/'.name
  if !isdirectory(folder) && exists('*mkdir')
    call mkdir(folder, 'p')
  endif

  for file in files
    let segments = split(file, '/\|\\')
    let diff_cmd = s:GetDiffCmd(file)
    if len(segments) == 1
      let cmd = diff_cmd.' > '.folder.'/'.file.'.diff'
    else
      let dir = segments[:-2]
      let filename = segments[-1]
      let diff_file = s:GetDiffFilePath(dir, filename)
      let cmd = diff_cmd.' > '.folder.'/'.diff_file.'.diff'
    endif
    call project#RunShellCmd(cmd)
    if v:shell_error
      break
    endif
  endfor

  call s:ShowStatus(1)
  call s:CloseBuffer(s:diff_buffer)
endfunction

function! s:GetDiffFileByLine(lnum)
  let folder = s:GetBelongFolder(a:lnum)
  let folder_name = folder.name
  let dir = split(s:GetDirectoryByLine(a:lnum), '/\|\\')
  let filename = s:GetFilenameByLine(a:lnum)
  if len(dir) == 0
    let diff_file = filename
  else
    let diff_file = s:GetDiffFilePath(dir, filename)
  endif
  let shelf_folder = s:GetShelfFolder()
  return shelf_folder.'/'.folder_name.'/'.diff_file
endfunction

function! s:UnshelfFile() range
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)
  if empty(folder)
    let lines = range(a:firstline, a:lastline)
    let files = map(lines, {idx, v -> s:GetDiffFileByLine(v)})
    let diff_files = join(files, ' ')
  else
    let folder_name = folder.name
    let files = folder.files
    let shelf_folder = s:GetShelfFolder()
    let diff_files = join(map(copy(files), {idx, v -> shelf_folder.'/'.folder_name.'/'.v}), ' ')
  endif
  let cmd = 'git apply '.diff_files
  call project#RunShellCmd(cmd)
  call s:ShowStatus(1)
endfunction

function! s:RollbackFile() range
  let files = []
  for lnum in range(a:firstline, a:lastline)
    let file = s:GetFileByLine(lnum)
    if !empty(file)
      call add(files, file)
    endif
  endfor
  if empty(files)
    return
  endif

  let saved_pos = getpos('.')
  echo 'Rollback changes of ['.join(files, ', ').']? (y/n) '
  if nr2char(getchar()) == 'y'
    for file in files
      let diff_file = s:TryGetDiffFile(file)
      if !empty(diff_file)
        let cmd = 'rm '.diff_file
      elseif s:IsFileUntracked(file)
        let cmd = 'git clean -fd "'.file.'"'
      else
        let cmd = 'git restore -- "'.file.'"'
      endif
      call project#RunShellCmd(cmd)
      if v:shell_error
        return
      endif
      call s:ShowStatus(1)
      call s:CloseBuffer(s:diff_buffer)
    endfor
  endif
  call setpos('.', saved_pos)

  redraw
  echo
endfunction

function! s:IsFileUntracked(file)
  let cmd = 'git ls-files --error-unmatch "'.a:file.'"'
  call project#RunShellCmd(cmd, 0)
  return v:shell_error
endfunction

function! s:IsUserFolder(folder)
  return !empty(a:folder) && !s:IsDefaultFolder(a:folder) && !s:IsSpecialFolder(a:folder)
endfunction

function! s:DeleteFolder()
  let lnum = line('.')
  let folder = s:GetCurrentFolder(lnum)
  if s:IsShelfFolder(folder)
    let shelf_folder = s:GetShelfFolder()
    let folder_path = shelf_folder.'/'.folder.name
    let cmd = 'rm -fr '.folder_path
    call project#RunShellCmd(cmd)
  endif

  if s:IsUserFolder(folder)
    call remove(s:changelist, index(s:changelist, folder))
  endif
  call s:ShowStatus()
  execute lnum
endfunction

function! VimProjectUserFolderNames(A, L, P)
  let folder = s:GetBelongFolder(line('.'))

  let changelist = filter(copy(s:changelist), {idex, v -> !s:IsShelfFolder(v)})
  let folder_names = map(changelist, {idx, v -> v.name})
  call filter(folder_names, {idx, v -> 
        \v != s:untracked_folder_name 
        \&& v != s:unmerged_folder_name 
        \&& v != s:staged_folder_name
        \&& v != folder.name
        \&& v =~ a:A
        \})
  return folder_names
endfunction

function! VimProjectShelfFolderNames(A, L, P)
  let folder = s:GetBelongFolder(line('.'))

  let changelist = filter(copy(s:changelist), {idex, v -> s:IsShelfFolder(v)})
  let folder_names = map(changelist, {idx, v -> v.name})
  call filter(folder_names, {idx, v -> v =~ a:A})
  return folder_names
endfunction

function! s:NewChangelistFolder()
  let name = input('New changelist name: ')
  if empty(name)
    return
  endif

  let target = s:GetChangelistItem(name)
  if empty(target)
    call s:AddNewFolder(name, [])
    call s:ShowStatus()
    if !empty(name)
      call search(name)
    endif
  else
    call project#Warn('Changelist with name ['.name.'] already exists')
  endif
endfunction

function! s:IsInvalidMoveToName(name)
  return empty(a:name) || a:name == s:staged_folder_name || a:name == s:unmerged_folder_name
endfunction

function! s:MoveToFolder() range
  let lnum = line('.')
  let belong_folder = s:GetBelongFolder(lnum)
  if s:IsStagedFolder(belong_folder) || s:IsUnmergedFolder(belong_folder)
    return
  endif

  let folder = s:GetCurrentFolder(lnum)

  if !empty(folder)
    let name = input('Move to: ', '', 'customlist,VimProjectUserFolderNames')
    if s:IsInvalidMoveToName(name)
      return
    endif

    call s:MoveFolderTo(folder, name)
  else
    let file = s:GetCurrentFile()
    if !empty(file)
      let name = input('Move to: ', '', 'customlist,VimProjectUserFolderNames')
      if s:IsInvalidMoveToName(name)
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
  let file = s:GetFileByLine(a:from_lnum)
  if empty(file)
    return
  endif
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

function! s:GetCurrentMatchstr(regexp)
  return s:GetMatchstrByLine(line('.'), a:regexp)
endfunction

function! s:GetMatchstrByLine(lnum, regexp)
  return matchstr(getline(a:lnum), a:regexp)
endfunction

" Get file in changelist
function! s:GetCurrentFile()
  return s:GetFileByLine(line('.'))
endfunction

function! s:GetDirectoryByLine(lnum)
  return s:GetMatchstrByLine(a:lnum, s:directory_regexp)
endfunction

function! s:GetFilenameByLine(lnum)
  return s:GetMatchstrByLine(a:lnum, s:file_regexp)
endfunction

function! s:GetFileByLine(lnum)
  let name = s:GetFilenameByLine(a:lnum)
  let directory = s:GetDirectoryByLine(a:lnum)
  if empty(directory)
    return name
  endif
  return directory.'/'.name
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

function! s:GetFileChangeSign(file)
  return split(a:file, '\s\+')[0]
endfunction

function! s:GetFilename(file)
  return substitute(a:file, '^\S\+\s\+', '', 'g')
endfunction

function! s:GetPrefixAndSuffix(folder)
  let expand = '▼'
  let collapse = '▶'
  let empty = '-'

  let prefix = a:folder.expand ? expand : collapse
  let suffix = ''

  let file_num = 0
  if s:IsStagedFolder(a:folder)
    let affected_files = s:staged_files
  elseif s:IsUnmergedFolder(a:folder)
    let affected_files = s:unmerged_files
  else
    let affected_files = s:changed_files + s:untracked_files
  endif
  for file in (affected_files)
    if s:HasFile(a:folder.files, file)
      let file_num += 1
    endif
  endfor

  if s:IsShelfFolder(a:folder)
    let file_num = len(a:folder.files)
  endif

  if !file_num
    let prefix = empty
  elseif file_num == 1
    let suffix = file_num.' file'
  else
    let suffix = file_num.' files'
  endif

  if s:IsShelfFolder(a:folder)
    let prefix = prefix.' '.s:shelf_folder_prefix
  endif
  return [prefix, suffix]
endfunction

function! s:AddUntrackedPrefix(files)
  return map(copy(a:files), {idx, file -> 'U	'.file})
endfunction

function! s:UpdatePresetChangelist()
  let unmerged_folder = s:FindUnmergedFolder()
  let unmerged_folder.files = []
  for file in s:unmerged_files
    call add(unmerged_folder.files, s:GetFilename(file))
  endfor

  let untracked_folder = s:FindUntrackedFolder()
  let untracked_folder.files = []
  for file in s:untracked_files
    let included = 0
    for folder in s:changelist
      if s:HasFile(folder.files, file)
        let included = 1
      endif
    endfor

    if !included
      call add(untracked_folder.files, s:GetFilename(file))
    endif
  endfor

  let default_folder = s:changelist[0]
  let default_folder.files = []
  for file in (s:changed_files + s:untracked_files)
    let included = 0
    for folder in s:changelist
      if s:IsStagedFolder(folder)
        continue
      endif
      if s:HasFile(folder.files, file)
        let included = 1
      endif
    endfor

    if !included
      call add(default_folder.files, s:GetFilename(file))
    endif
  endfor

  let staged_folder = s:FindStagedFolder()
  let staged_folder.files = []
  for file in s:staged_files
    call add(staged_folder.files, s:GetFilename(file))
  endfor
endfunction

function! s:UpdateFolderOrNew(name, files)
  for folder in s:changelist
    if folder.name == a:name
      let folder.files = a:files
      return
    endif
  endfor

  let new = {
        \ 'name': a:name,
        \ 'files': a:files,
        \ 'expand': 0,
        \ 'shelf': 1,
        \}

  call add(s:changelist, new)
endfunction

function! s:IsShelfFolder(folder)
  return !empty(a:folder) && has_key(a:folder, 'shelf')
endfunction

function! s:UpdateShelfChangelist()
  let shelf_folder = s:GetShelfFolder()
  if !isdirectory(shelf_folder)
    return
  endif
  let cmd = 'ls '.shelf_folder
  let folder_names = project#RunShellCmd(cmd)
  for folder_name in folder_names
    let folder_path = shelf_folder.'/'.folder_name
    if isdirectory(folder_path)
      let folder_path_cmd = 'ls '.folder_path
      let files = project#RunShellCmd(folder_path_cmd)
      call s:UpdateFolderOrNew(folder_name, files)
    endif
  endfor
endfunction

function! s:UpdateChangelistDisplay()
  let s:display = []
  for folder in s:changelist
    if s:IsSpecialFolder(folder) && empty(folder.files)
      continue
    endif
    let [prefix, suffix] = s:GetPrefixAndSuffix(folder)
    let folder_item = prefix.' |'.folder.name.' '.suffix
    call add(s:display, folder_item)
    if folder.expand
      if s:IsStagedFolder(folder)
        let affected_files = s:staged_files
      elseif s:IsUnmergedFolder(folder)
        let affected_files = s:unmerged_files
      else
        let affected_files = s:changed_files + s:untracked_files
      endif

      if s:IsShelfFolder(folder)
        for file in folder.files
          let file_item = s:GetShelfFileDisplay(file)
          call add(s:display, file_item)
        endfor
      else
        let all_files = s:SortAffectedFiles(affected_files)
        for file in all_files
          if s:HasFile(folder.files, file)
            let file_item = s:GetChangedFileDisplay(file)
            call add(s:display, file_item)
          endif
        endfor
      endif
    endif
    call add(s:display, '')
  endfor
endfunction

function! s:SortAffectedFiles(files)
  return sort(copy(a:files), function('s:SortAffectedFilesFunc'))
endfunction

function! s:SortAffectedFilesFunc(i1, i2)
  let filename_1 = s:GetFilename(a:i1)
  let name_1 = fnamemodify(filename_1, ':t')
  let filename_2 = s:GetFilename(a:i2)
  let name_2 = fnamemodify(filename_2, ':t')
  return name_1 == name_2 ? 0 : name_1 > name_2 ? 1 : -1
endfunction

function! s:GetChangedFileDisplay(file, prefix = '  ')
  let sign = s:GetFileChangeSign(a:file)
  " sign_mark is used by s:HighlightFiles
  let sign_mark = ''
  if sign == 'D' 
    let sign_mark = '$'  " $ Deleted - Comment
  elseif sign == 'A' || sign == '?' 
    let sign_mark = '!'  " ! Add or untrack - diffAdded
  endif
  let splitter = '|'

  let filename = s:GetFilename(a:file)
  if isdirectory(filename)
    let dir = ''
    let name = filename
  else
    let name = fnamemodify(filename, ':t')
    let file_dir = fnamemodify(s:GetAbsolutePath(filename), ':p:h')
    let project_dir = project#GetProjectDirectory()
    if file_dir == project_dir[0:-2]
      let dir = ''
    else
      let project_dir_pat = escape(fnamemodify(project_dir, ':p'), '\')
      let dir = substitute(file_dir, project_dir_pat, '', '')
    endif
  endif
  let icon = project#GetIcon(filename)

  " Use unicode space for highlight 
  let dir = substitute(dir, ' ', ' ', '')
  if empty(name)
    return a:prefix.sign_mark.icon.splitter.dir.' '
  else
    return a:prefix.sign_mark.icon.splitter.name.splitter.' '.dir
  endif
endfunction

function! s:GetShelfFileDisplay(file, prefix = '  ')
  " sign_mark is used by s:HighlightFiles
  let sign_mark = ''
  let splitter = '|'
  let icon = project#GetIcon(a:file)
  let segments = split(a:file, s:shelf_path_file_spliter)
  if len(segments) == 1
    return a:prefix.sign_mark.icon.splitter.a:file.splitter.' '
  else
    let dir = substitute(segments[0], s:shelf_path_spliter, '/', '')
    let filename = segments[1]
    return a:prefix.sign_mark.icon.splitter.filename.splitter.' '.dir
  endif
endfunction

function! s:UpdateChangelist(run_git = 0)
  if a:run_git
    call s:ParseGitStatus()
  endif

  call s:UpdatePresetChangelist()
  call s:UpdateShelfChangelist()
  call s:UpdateChangelistDisplay()
  return 1
endfunction

function! s:ParseGitStatus()
  let output = project#RunShellCmd('git status --porcelain')
  let s:staged_files = []
  let s:changed_files = []
  let s:untracked_files = []
  let s:unmerged_files = []

  for line in output
    let status = strpart(line, 0, 2)
    let filepath = strpart(line, 3)

    if status[0] != ' ' && status[0] != '?' && status[0] != 'U' " Staged files
      call add(s:staged_files, status[0].' '.filepath)
    endif

    if status[0] == ' ' && status[1] != ' ' " Changed but unstaged files
      call add(s:changed_files, status[1].' '.filepath)
    endif

    if status == '??' " Untracked files
      call add(s:untracked_files, '? '.filepath)
    endif

    if status == 'UU' " Merge conflicts
      call add(s:unmerged_files, 'U '.filepath)
    endif
  endfor
endfunction

function! s:IsSpecialFolder(folder)
  return s:IsStagedFolder(a:folder)
        \ || s:IsUntrackedFolder(a:folder) 
        \ || s:IsUnmergedFolder(a:folder)
endfunction

function! s:FindUnmergedFolder()
  for folder in s:changelist
    if s:IsUnmergedFolder(folder)
      return folder
    endif
  endfor

  let default_folder = s:changelist_default[-3]
  call add(s:changelist, default_folder)
  return default_folder
endfunction

function! s:FindUntrackedFolder()
  for folder in s:changelist
    if s:IsUntrackedFolder(folder)
      return folder
    endif
  endfor

  let default_folder = s:changelist_default[-2]
  call add(s:changelist, default_folder)
  return default_folder
endfunction

function! s:FindStagedFolder()
  for folder in s:changelist
    if s:IsStagedFolder(folder)
      return folder
    endif
  endfor

  let default_folder = s:changelist_default[-1]
  call add(s:changelist, default_folder)
  return default_folder
endfunction

function! s:IsDefaultFolder(folder)
  return a:folder.name == s:default_folder_name
endfunction

function! s:IsStagedFolder(folder)
  return a:folder.name == s:staged_folder_name
endfunction

function! s:IsUntrackedFolder(folder)
  return a:folder.name == s:untracked_folder_name
endfunction

function! s:IsUnmergedFolder(folder)
  return a:folder.name == s:unmerged_folder_name
endfunction

function! s:HasFile(files, file)
  let filename = s:GetFilename(a:file)
  return count(a:files, filename)
endfunction

function! s:OnChangelistBuffer()
  let num = s:GetBufWinnr(s:changelist_buffer)
  return num != -1
endfunction

function! s:ShowStatus(run_git = 0)
  call s:CloseBuffer(s:commit_result_buffer)

  " Ignore events to avoid a cursor bug when opening from Fern.vim
  let save_eventignore = &eventignore
  set eventignore=all

  let on_changelist_buffer = s:OnChangelistBuffer()
  if on_changelist_buffer
    let lnum = line('.')
  endif

  call s:OpenBuffer(s:changelist_buffer, 'belowright')
  call s:SetupChangelistBuffer()
  let success = s:UpdateChangelist(a:run_git)
  if success
    call s:WriteChangelist()
    call s:HighlightChangelist()
  endif

  let &eventignore = save_eventignore

  if on_changelist_buffer
    execute lnum
  endif
endfunction

function! s:SetupChangelistBuffer()
  let mappings = project#GetVariable('git_local_changes_mappings')
  call s:AddMapping(mappings.open_changelist_or_file, '<SID>OpenFolderOrFile()')
  call s:AddMapping(mappings.delete_changelist, '<SID>DeleteFolder()')
  call s:AddMapping(mappings.rename_changelist, '<SID>RenameFolder()')
  call s:AddMapping(mappings.rollback_file, '<SID>RollbackFile()')
  call s:AddVisualMapping(mappings.rollback_file, '<SID>RollbackFile()')
  call s:AddMapping(mappings.commit, '<SID>Commit()')
  call s:AddVisualMapping(mappings.commit, '<SID>Commit()')
  call s:AddMapping(mappings.pull, '<SID>TryPull()')
  call s:AddMapping(mappings.push, '<SID>TryPush()')
  call s:AddMapping(mappings.pull_and_push, '<SID>TryPullThenPush()')
  call s:AddMapping(mappings.force_push, '<SID>TryPush(1)')
  call s:AddMapping(mappings.new_changelist, '<SID>NewChangelistFolder()')
  call s:AddMapping(mappings.move_to_changelist, '<SID>MoveToFolder()')
  call s:AddVisualMapping(mappings.move_to_changelist, '<SID>MoveToFolder()')
  call s:AddMapping(mappings.shelf, '<SID>ShelfFile()')
  call s:AddVisualMapping(mappings.shelf, '<SID>ShelfFile()')
  call s:AddMapping(mappings.unshelf, '<SID>UnshelfFile()')
  call s:AddVisualMapping(mappings.unshelf, '<SID>UnshelfFile()')

  hi DiffBufferModify ctermfg=3 guifg=#b58900
  hi DiffBufferAdd ctermfg=2 guifg=#719e07
  hi DiffBufferDelete ctermfg=9 guifg=#dc322f
  syntax match DiffBufferModify /^\s\sM\ze\s/
  syntax match DiffBufferAdd /^\s\sA\ze\s/
  syntax match DiffBufferDelete /^\s\sD\ze\s/
  syntax match Splitter "|" conceal
  syntax match Splitter "\$" conceal
  syntax match Splitter "!" conceal
  setlocal conceallevel=3 
  setlocal concealcursor=nvc

  setlocal buftype=nofile
  setlocal nomodifiable
  setlocal nonumber
  setlocal nowrap

  autocmd CursorMoved <buffer> call s:ShowDiffOnChangelist()
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
  autocmd BufUnload <buffer> call s:WriteChangelistFile()
  let s:current_line = 1
endfunction

function! s:WriteChangelist()
  setlocal modifiable
  call execute('normal! gg"_dG', 'silent!')
  call append(0, s:display)
  normal gg
  setlocal nomodifiable
endfunction

function! s:HighlightChangelist()
  call s:HighlightFiles(s:display)
  call matchadd('Keyword', s:folder_regexp)
  call matchadd('Comment', '\d\+ files\?')
  call matchadd('Normal', s:staged_folder_name)
  call matchadd('Normal', s:unmerged_folder_name)
endfunction

function! s:HighlightFiles(lines)
  call clearmatches()
  let index = 1
  for line in a:lines
    let line_pattern = '\%'.index.'l'
    if line =~ '\$'
      call matchadd('Comment', line_pattern)
    elseif line =~ '!'
      call matchadd('diffAdded', line_pattern)
    endif
    call matchadd('Comment', line_pattern.' \S*$')
    let index += 1
  endfor
  call project#HighlightIcon()
endfunction

function! s:Commit() range
  let files = []

  let lnum = line('.')
  if getline(lnum) =~ '^\s*$'
    return
  endif

  let file = s:GetCurrentFile()
  if empty(file)
    let folder = s:GetBelongFolder(lnum)
    let files = folder.files
  else
    let files = []
    for lnum in range(a:firstline, a:lastline)
      call add(files, s:GetFileByLine(lnum))
    endfor
  endif

  let check_files = s:changed_files + s:untracked_files + s:staged_files + s:unmerged_files
  let commit_files = filter(check_files, {idx, file -> s:HasFile(files, file)}) 
  if empty(commit_files)
    return 
  endif
  let s:commit_files = uniq(map(copy(commit_files), {idx, file -> s:GetFilename(file)}))
  let show_commit_files = map(copy(commit_files), {idx, file -> '#    '.file})

  let title = s:GetCommitMessage()
  quit
  call s:ShowCommitMessage(title, show_commit_files)
endfunction

function! s:RemoveFolderNamePrefix(name)
  return substitute(a:name, '^\d*\. ', '', 'g')
endfunction

function! s:GetCommitMessage()
  let lnum = line('.')
  let folder = s:GetBelongFolder(lnum)
  let folder_name = !empty(folder) ? s:RemoveFolderNamePrefix(folder.name) : ''

  let title = ''
  let CustomMessage = project#GetVariable('commit_message')

  if !empty(CustomMessage)
    if type(CustomMessage) == type(function('tr'))
      let title = CustomMessage(folder_name)
    elseif type(CustomMessage) == type('')
      let title = CustomMessage
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
        \'# Changes to be committed:'
        \]
  execute 'new '.s:commit_edit_buffer
  let content = [a:title] + preset_message + a:files
  call append(0, content)
  normal! gg

  setlocal buftype=nofile bufhidden=wipe nobuflisted filetype=gitcommit
  syntax match Normal /#\s\{4}\zs.*/ containedin=gitcommitSelected
  autocmd WinClosed <buffer> ++once call s:TryCommit()
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

  let files = join(map(s:commit_files, {idx, val -> '"'.val.'"'}), ' ')
  let message = join(map(message_lines, {idx, val -> '-m "'.escape(val, '"`').'"'}), ' ')

  let option = ''
  if is_amend
    let option = option.' --amend --no-edit'
  endif

  let cmd = 'git add '.files.' && git commit '.message.option
  let result = project#RunShellCmd(cmd)

  quit
  call s:OpenResultWindow(s:commit_result_buffer, cmd, result)

  let mappings = project#GetVariable('git_local_changes_mappings')
  call s:AddMapping(mappings.pull, '<SID>TryPull()')
  call s:AddMapping(mappings.push, '<SID>TryPush()')
  call s:AddMapping(mappings.pull_and_push, '<SID>TryPullThenPush()')
  call s:AddMapping(mappings.force_push, '<SID>TryPush(1)')
endfunction

function! s:TryPush(force=0)
  call project#Info(a:force ? 'Force pushing...' : 'Pushing...')
  let cmd = a:force ? 'git push -f' : 'git push'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  redraw
  if len(result) == 1
    call project#Info(result[0])
  else
    call project#Info('Pushed sucessfully')
  endif
  call s:CloseBuffer(s:commit_result_buffer)
endfunction

function! s:TryPullThenPush()
  call s:TryPull()
  if v:shell_error
    return
  endif

  call s:TryPush()
endfunction

function! s:TryPull()
  call project#Info('Updating...') 
  let cmd = 'git pull'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  redraw
  if len(result) == 1
    call project#Info(result[0])
  else
    call project#Info('Updated sucessfully')
  endif
  call project#search_files#Reset()
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
  call append(0, [a:cmd, s:item_splitter, ''] + a:result)
  setlocal buftype=nofile
  syntax match Constant /\[\zs\w*\ze .*\]/
  syntax match Keyword /\s\zs\d\+\ze\s\(files\? changed\|insertion\|deletion\)/
  normal! gg
endfunction
