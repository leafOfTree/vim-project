let s:current_line = 0
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


function! project#git#file_history(...)
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif
    call project#Warn('Open a file first to show its history')
  let range = a:000[0]
  let prompt = 'History of '.filename.':' 
  let s:file_history_range = []
  if range > 0
    let s:file_history_range = [line("'<"), line("'>")]
    let prompt = 'History of '.filename.' L'.join(s:file_history_range, ',').':' 
  endif

  call project#PrepareListBuffer(prompt, 'GIT_FILE_HISTORY')
  let range = s:GetLineRange()
  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:log_splitter)
  let cmd = 'git log --pretty=format:"'.format.'" --date=relative '.range.s:current_file
  if empty(range)
    let s:commit_diffs = []
  else
    let [logs, s:commit_diffs] = s:SaveCommitDiff(logs)
  endif

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

  let changes = []
  let is_diff_on_range = !empty(s:commit_diffs)
  if is_diff_on_range
    let changes = s:commit_diffs[a:hash]
  else
    let cmd = 'git show --pretty=format:"" '.a:hash.' '.a:file
    let changes = project#RunShellCmd(cmd)
  endif


  if is_diff_on_range
    silent! 1,3d
  else
    silent! 1,4d
  endif
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  let format = join(["%s", "%aN", "%ae", "%ad", "%h"], s:log_splitter)
  let num = s:GetBufWinnr(a:search)
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

  let nr = s:GetBufnr(a:name)
  call s:WriteChangelistFile(s:changelist)
  if mode() != 'n'
  let lnum = line('.')
  let is_first_line = lnum == 1
  let no_moving = lnum == s:current_line
  if is_first_line || no_moving
    return 
  endif

  let s:current_line = lnum

  let file = s:GetCurrentFile(lnum)
  if empty(file)
    return
  endif
  call s:AddChangeDetails(file)
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
  if empty(changes)
    " For untracked files
    " Have to add ' || true' as 'git diff --no-index' returns 0 for no changes, 1 changes
    let cmd = 'git diff --no-index -- /dev/null '.a:file.' || true'
    let changes = project#RunShellCmd(cmd)
  endif

  if mode() != 'n'
    return
  endif

  call add(brief, '----------------------------------------------------------------------------')
    let [message, author, email, date, hash] = split(log, s:log_splitter, 1)
    let date = s:ShortenDate(date)
    call insert(list, 
          \{ 'message': message, 'author': author, 'date': date, 'hash': hash, 'email': email })
function! s:ShortenDate(origin)
  let date = substitute(a:origin, 'years\?', 'y', 'g')
  let date = substitute(date, 'months\?', 'm', 'g')
  let date = substitute(date, 'weeks\?', 'w', 'g')
  let date = substitute(date, 'days\?', 'd', 'g')
  return date
endfunction

function! project#git#status()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  " Manually trigger some events first
  silent doautocmd BufLeave
  silent doautocmd FocusLost
  call s:LoadChangelist()
  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

  if !project#ProjectExist()
    call project#Warn('Open a project first')
    return
  endif

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

function! s:WriteChangelistFile(changelist)
  let changelist_string = json_encode(a:changelist)
  call writefile([changelist_string], s:GetChangelistFile())
endfunction
  let changelist = s:ReadChangelistFile()
  if !empty(changelist)
    let s:changelist = changelist
  else
    let s:changelist = s:changelist_default
  endif
endfunction

function! s:ToggleFolderOrOpenFile()
  let item = s:GetCurrentFolder(lnum)
  else
    let file = s:GetCurrentFile(lnum)
    if !empty(file)
      wincmd k
      execute 'e '.$vim_project.'/'.file
    endif
function! s:RenameFolder()
  let lnum = line('.')
  let item = s:GetCurrentFolder(lnum)
  if s:IsUserFolder(item)
    let name = input('Rename '.item.name.', new name: ')
    if !empty(name)
      let item.name = name
      call s:ShowStatus()
      execute lnum
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
    let name = input('Move to Another Changelist, name: ', '', 'customlist,VimProjectAllFolderNames')
    if empty(name)
      return
    endif

    call s:MoveFolderTo(folder, name)
  else
    let file = s:GetCurrentFile(lnum)
    if !empty(file)
      let name = input('Move to Another Changelist, name: ', '', 'customlist,VimProjectAllFolderNames')
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
  execute lnum
endfunction

function! s:MoveFolderTo(from_folder, to_name)
  let files = a:from_folder.files
  let a:from_folder.files = []
  let target = s:GetChangelistItem(a:to_name)
  if empty(target)
    let target = {
          \ 'name': a:to_name,
          \ 'files': files,
          \ 'expand': 1,
          \}
    call insert(s:changelist, target, -1)
  else
    call extend(target.files, files)
    let target.expand = 1
  endif
function! s:MoveFileTo(from_lnum, to_name) 
  let cur_line = getline(a:from_lnum)
  let from_folder = s:GetBelongFolder(a:from_lnum)
  call filter(from_folder.files, 'v:val != "'.file.'"')
  let target = s:GetChangelistItem(a:to_name)
          \ 'name': a:to_name,
function! s:GetBelongFolder(lnum)
  return s:GetCurrentFolder(lnum)
function! s:GetCurrentFolder(lnum)
  elseif file_num == 1
    let suffix = file_num.' file'
  let s:changelist[-1].files = []
function! s:UpdateChangelist(run_git = 0)
  if a:run_git
function! s:ShowStatus(run_git = 0)
  call s:OpenBuffer(s:changelist_buffer_search, s:changelist_buffer, 'belowright')
  let success = s:UpdateChangelist(a:run_git)
  nnoremap<buffer><silent> o :call <SID>ToggleFolderOrOpenFile()<cr>
  nnoremap<buffer><silent> r :call <SID>RenameFolder()<cr>
  nnoremap<buffer><silent> d :call <SID>DeleteFolder()<cr>
  nnoremap<buffer><silent> p :call <SID>TryPush()<cr>

  noremap<buffer><silent> m :call <SID>MoveToChangelist()<cr>

  syntax match Comment /\d\+ files\?/
  setlocal nomodifiable

  let s:current_line = 0
  setlocal modifiable
  call execute('normal! ggdG', 'silent!')
  setlocal nomodifiable
    let folder = s:GetBelongFolder(lnum)
  let amend_lines = filter(getline(0, line('$')), {idx, val -> val =~ '^amend$'})
    call project#Info('Commit canceled')
  call s:OpenResultWindow('COMMIT_RESULT', cmd, result)
  nnoremap<buffer><silent> u :call <SID>TryPull()<cr>
  nnoremap<buffer><silent> p :call <SID>TryPush()<cr>
  redraw
  call s:ShowResultMessage(result)
  call project#Info('Updating...') 
  redraw
  call s:ShowResultMessage(result)
endfunction

function! s:ShowResultMessage(result)
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