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

  let cmd = 'git log --pretty=format:"'.format.'" --date=relative '.s:current_file
  let s:list = s:GetTabulatedList(logs)
  call s:ShowDiffOfCurrentFile()
function! s:ShowDiffOfCurrentFile()
  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:AddDiffDetails(revision.hash, s:current_file)
  call s:AddBrief(revision)
  call s:SetupDiffBuffer()
  wincmd h
endfunction

function! s:AddDiffDetails(hash, file)
  let format = ""
  let cmd = 'git show --pretty=format:"'.format.'" '.a:hash.' -- '.a:file
  let changes = project#RunShellCmd(cmd)
  silent! g/^new file mode/d
  silent! 1,4d
endfunction

function! s:AddBrief(revision)
  let brief = s:GenerateBrief(a:revision)
  call append(line('$'), brief)
endfunction

function! s:SetupDiffBuffer()
  call s:CloseBuffer(s:diff_buffer_search)
  call project#SetVariable('initial_height', winheight(0) - 5)
  let cmd = 'git log --pretty=format:"'.format.'" --date=relative'
  let s:list = s:GetTabulatedList(logs)
  call s:ShowCurrentChangdFiles()
endfunction
function! s:ShowCurrentChangdFiles()
  if empty(changed_files)
    return

  call s:OpenBuffer(s:changes_buffer_search, s:changes_buffer, 'vertical')
  call s:SetupChangesBuffer(revision)
  call s:AddToBuffer(revision)
  wincmd h

  execute 'autocmd CursorMoved <buffer> call s:ShowDiffOfCurrentLine("'.a:revision.hash.'")'
  call s:CloseChangesBuffer()
    execute 'silent '.a:pos.' new '.a:name
  setlocal buftype=nofile bufhidden=wipe nobuflisted
  if bufname() == a:name
    quit
    return
  endif

    execute 'silent! bdelete '.nr
    if empty(bufname())
      quit
    endif
  call s:CloseBuffer(s:changes_buffer_search)
  call s:CloseBuffer(s:before_buffer_search)
  call s:CloseBuffer(s:after_buffer_search)
  call s:CloseBuffer(s:diff_buffer_search)
  setlocal buftype=nofile bufhidden=wipe nobuflisted
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
endfunction

function! s:ShowChangeOfCurrentLine()
  let file = s:GetCurrentFile(line('.'))
  if empty(file)
    return
  endif
  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:AddChangeDetails(file)
  call s:SetupDiffBuffer()
  wincmd h
endfunction

function! s:AddChangeDetails(file)
  let cmd = 'git diff '.a:file
  let changes = project#RunShellCmd(cmd)
  call append(0, changes)
  normal! gg
  silent! g/^new file mode/d
  silent! 1,4d
endfunction

function! s:ShowDiffOfCurrentLine(hash)
  let line = getline('.')
  let file = matchstr(line, '^\S\s\zs.*')
  if empty(file)
    return
  endif

  call s:OpenBuffer(s:diff_buffer_search, s:diff_buffer, 'vertical')
  call s:AddDiffDetails(a:hash, file)
  call s:SetupDiffBuffer()
  wincmd h
function! s:ShowDiffSideBySide(hash)
  call s:OpenBuffer(s:before_buffer_search, s:before_buffer.' '.filename, 'botright')
  call s:OpenBuffer(s:after_buffer_search, s:after_buffer.' '.filename, 'vertical')
  let changed_files = map(project#RunShellCmd(cmd), 'substitute(v:val, "\t", " ", "")')
  call add(brief, '-------------------')
function! s:GetTabulatedList(logs)
  return a:value.__message.' '.a:value.__author.' '.a:value.__date
endfunction

function! project#git#commit()
  call s:ShowStatus(1)
endfunction

function! project#git#push()
  call s:TryPush()
endfunction

function! project#git#pull()
  call s:TryPull()
endfunction

let s:default_folder_name = 'Default'
let s:untracked_folder_name = 'Untracked'
let s:changed_files = []
let s:untracked_files = []
let s:commit_files = []
let s:file_regexp = '^\s\+\S\s\+\zs.*'
let s:folder_regexp = '^\S\s\zs\w\+'

function! s:LoadChangelist()
  let s:changelist = [
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
endfunction

function! s:ToggleFolder()
  let lnum = line('.')
  let item = s:GetFolderItem(lnum)
  if !empty(item)
    let item.expand = 1 - item.expand
    call s:ShowStatus()
    execute lnum
  endif
endfunction

function! s:MoveToChangelist() range
  let cur_line = getline('.')
  if cur_line !~ s:file_regexp
    return
  let name = input('Move to Another Changelist, name: ')
  if empty(name)
    let name = s:default_folder_name
  endif

  for lnum in range(a:firstline, a:lastline)
    call s:MoveTo(lnum, name)
  endfor

  call s:ShowStatus()
endfunction

function! s:MoveTo(lnum, name) 
  let cur_line = getline(a:lnum)
  if cur_line !~ s:file_regexp
    return
  endif

  let target = {}
  for item in s:changelist
    if item.name == a:name
      let target = s:GetChangelistItem(a:name)
    endif
  endfor

  let file = matchstr(cur_line, s:file_regexp)
  let current = s:GetCurrentFolder(a:lnum)
  call filter(current.files, 'v:val != "'.file.'"')

  if empty(target)
    let target = {
          \ 'name': a:name,
          \ 'files': [file],
          \ 'expand': 1,
          \}
    call insert(s:changelist, target, -1)
  else
    call add(target.files, file)
    let target.expand = 1
  endif
endfunction

function! s:GetCurrentFile(lnum)
  return matchstr(getline(a:lnum), s:file_regexp)
endfunction

function! s:GetCurrentFolder(lnum)
  let lnum = a:lnum
  while getline(lnum) !~ s:folder_regexp && lnum > -1
    let lnum = lnum - 1
  endwhile
  return s:GetFolderItem(lnum)
endfunction

function! s:GetFolderItem(lnum)
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

function! s:UpdateChangelist(refresh_data = 0)
  if a:refresh_data
    let s:changed_files = project#RunShellCmd('git diff --name-status head')
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

function! s:ShowStatus(refresh_data = 0)
  " Ignore events to avoid a cursor bug when opening from Fern.vim
  let save_eventignore = &eventignore
  set eventignore=all

  call s:LoadChangelist()
  call s:OpenBuffer(s:changelist_buffer_search, s:changelist_buffer, 'botright')
  call s:SetupChangelistBuffer()
  let success = s:UpdateChangelist(a:refresh_data)
  if success
    call s:WriteChangelist()
  endif

  let &eventignore = save_eventignore
endfunction

function! s:SetupChangelistBuffer()
  nnoremap<buffer><silent> o :call <SID>ToggleFolder()<cr>
  nnoremap<buffer><silent> m :call <SID>MoveToChangelist()<cr>
  nnoremap<buffer><silent> c :call <SID>Commit()<cr>
  nnoremap<buffer><silent> u :call <SID>TryPull()<cr>
  syntax match Comment /\d files/
  setlocal buftype=nofile
  execute 'syntax match Keyword /'.s:folder_regexp.'/'
  autocmd CursorMoved <buffer> call s:ShowChangeOfCurrentLine()
  autocmd BufUnload <buffer> call s:CloseChangesBuffer()
endfunction

function! s:WriteChangelist()
  call execute('normal ggdG', 'silent!')
  call append(0, s:display)
  normal gg
endfunction

function! s:Commit()
  let files = []
  let title = ''

  let lnum = line('.')
  if getline(lnum) =~ '^\s*$'
    return
  endif

  let file = s:GetCurrentFile(lnum)
  if empty(file)
    let folder = s:GetCurrentFolder(lnum)
    let files = folder.files
    let title = folder.name
    if title == s:default_folder_name
      let title = ''
    endif
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

  quit
  call s:ShowCommitMessage(title, show_commit_files)
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
  let message_lines = filter(getline(0, line('$')), {idx, val -> val =~ '^[^#]' && val !~ '^\s*$'})
  let amend_lines = filter(getline(0, line('$')), {idx, val -> val =~ '--amend'})
  let is_empty_message = empty(message_lines)
  let is_amend = !empty(amend_lines)
  if is_empty_message && !is_amend
    return
  endif

  let files = join(s:commit_files, ' ')
  let message = join(map(message_lines, {idx, val -> '-m "'.val.'"'}), ' ')

  let option = ''
  if is_amend
    let option = option.' --amend --no-edit'
  endif

  let cmd = 'git add '.files.' && git commit '.message.option
  let result = project#RunShellCmd(cmd)

  quit
  new COMMIT_RESULT
  call append(0, [cmd, ''] + result)
  setlocal buftype=nofile
  nnoremap<buffer><silent> p :quit<cr>:call project#git#push()<cr>
  normal! gg
endfunction

function! s:TryPush()
  call project#Info('Pushing...')
  let cmd = 'git push'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  new PUSH_RESULT
  call append(0, [cmd, ''] + result)
  setlocal buftype=nofile
  normal! gg
endfunction

function! s:TryPull()
  call project#Info('Updating...')
  let cmd = 'git pull'
  let result = project#RunShellCmd(cmd)
  if v:shell_error
    return 
  endif

  new UPDATE_RESULT
  call append(0, [cmd, ''] + result)
  setlocal buftype=nofile
  normal! gg