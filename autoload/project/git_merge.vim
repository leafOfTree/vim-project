" Resolve the merge conflicts of one file in a three-pane window, like the
" Merge dialog of IntelliJ IDEA:
"
"   yours (left) | result (middle) | theirs (right)
"
" The file is split into text and conflicts. Each conflict has a state:
" unresolved, left, right, both or manual. The panes are drawn from this
" model, with filler lines so that the conflicts line up, and signs color
" each conflict by its state. All panes are read-only: a choice is made by a
" key on the current conflict and can always be changed or undone. The file
" is written only on finish, once every conflict is resolved

let s:left_buffer = 'vim_project_merge_yours'
let s:result_buffer = 'vim_project_merge_result'
let s:right_buffer = 'vim_project_merge_theirs'
let s:edit_buffer = 'vim_project_merge_edit'
let s:unresolved_text = '(unresolved)'
let s:help_buffer = 'vim_project_merge_keys'

" The file being merged: {'file', 'segments', 'left_title', 'right_title'}.
" A segment is {'type': 'text', 'lines'} or {'type': 'conflict', 'left',
" 'base', 'right', 'state', 'result'}
let s:merge = {}
" Per segment {'start', 'height'} of the panes, set on rendering
let s:layout = []

" ---------------------------------------------------------------- state

" What git is in the middle of, from the files in the git directory. For a
" rebase git's "ours" is the branch being rebased onto, so yours is stage 3
function! project#git_merge#GetState()
  let git_dir = get(project#RunShellCmd('git rev-parse --absolute-git-dir', 0), 0, '')
  if empty(git_dir)
    return {}
  endif

  for dir in ['rebase-merge', 'rebase-apply']
    if isdirectory(git_dir.'/'.dir)
      return {'name': 'rebase', 'yours': 3, 'theirs': 2, 'rebase_dir': git_dir.'/'.dir,
            \'continue': 'git -c core.editor=true rebase --continue',
            \'abort': 'git rebase --abort'}
    endif
  endfor
  for [name, head] in [['merge', 'MERGE_HEAD'], ['cherry-pick', 'CHERRY_PICK_HEAD'], ['revert', 'REVERT_HEAD']]
    if filereadable(git_dir.'/'.head)
      let continue = name == 'merge'
            \? 'git commit --no-edit'
            \: 'git -c core.editor=true '.name.' --continue'
      return {'name': name, 'head': head, 'yours': 2, 'theirs': 3,
            \'continue': continue, 'abort': 'git '.name.' --abort'}
    endif
  endfor
  " Nothing in progress, yet conflicts: applying a stash, like after pull
  " --autostash. git's theirs is the stash, your local changes
  if !empty(project#git_merge#GetUnmergedFiles())
        \&& !empty(project#RunShellCmd('git stash list -n 1', 0))
    return {'name': 'stash', 'yours': 3, 'theirs': 2}
  endif
  return {}
endfunction

function! project#git_merge#GetUnmergedFiles()
  return project#RunShellCmd('git diff --name-only --diff-filter=U', 0)
endfunction

" Panes titles: where yours and theirs come from
function! s:GetTitles(state)
  let head = s:Describe('HEAD')
  if get(a:state, 'name', '') == 'rebase'
    " HEAD is detached: name the branches from what git saved for the rebase
    let branch = s:ReadRebaseFile(a:state, 'head-name')
    let branch = substitute(branch, '^refs/heads/', '', '')
    let rebase_head = s:ShortHash('REBASE_HEAD')
    let yours = empty(branch) ? rebase_head : branch.' '.rebase_head
    let onto = s:Describe(s:ReadRebaseFile(a:state, 'onto'))
    return ['Yours (being rebased) '.yours, 'Upstream (rebasing onto) '.onto]
  endif
  if has_key(a:state, 'head')
    return ['Yours '.head, 'Theirs '.s:Describe(a:state.head)]
  endif
  if get(a:state, 'name', '') == 'stash'
    return ['Yours (local changes, stashed)', 'Upstream '.head]
  endif
  return ['Yours '.head, 'Theirs']
endfunction

" Branch name or short hash of a revision, like 'main a1b2c3d'
function! s:ReadRebaseFile(state, name)
  let path = get(a:state, 'rebase_dir', '').'/'.a:name
  return filereadable(path) ? get(readfile(path), 0, '') : ''
endfunction

function! s:ShortHash(rev)
  return get(project#RunShellCmd('git rev-parse --short '.shellescape(a:rev), 0), 0, '')
endfunction

function! s:Describe(rev)
  if empty(a:rev)
    return ''
  endif
  let rev = shellescape(a:rev)
  let hash = s:ShortHash(a:rev)
  if empty(hash)
    return ''
  endif
  if a:rev == 'HEAD'
    let name = get(project#RunShellCmd('git branch --show-current', 0), 0, '')
  else
    let name = get(project#RunShellCmd('git name-rev --name-only --no-undefined '.rev, 0), 0, '')
  endif
  return empty(name) ? hash : name.' '.hash
endfunction

" ---------------------------------------------------------------- model

" Content of one stage of the file in the index, v:null if it has none, like
" the side that deleted the file
function! s:ReadStage(file, stage)
  let cmd = 'git show :'.a:stage.':'.shellescape(a:file)
  let lines = project#RunShellCmd(cmd, 0)
  return v:shell_error ? v:null : lines
endfunction

" Split the output of git merge-file --diff3 into text and conflicts
function! s:ParseMergeOutput(lines)
  let segments = []
  let text = []
  let conflict = {}
  let part = ''
  for line in a:lines
    if empty(part) && line =~# '^<<<<<<< '
      if !empty(text)
        call add(segments, {'type': 'text', 'lines': text})
        let text = []
      endif
      let conflict = {'type': 'conflict', 'left': [], 'base': [], 'right': [],
            \'state': '', 'result': []}
      let part = 'left'
    elseif part == 'left' && line =~# '^||||||| '
      let part = 'base'
    elseif (part == 'left' || part == 'base') && line =~# '^=======$'
      let part = 'right'
    elseif part == 'right' && line =~# '^>>>>>>> '
      call add(segments, conflict)
      let part = ''
    elseif empty(part)
      call add(text, line)
    else
      call add(conflict[part], line)
    endif
  endfor
  if !empty(text)
    call add(segments, {'type': 'text', 'lines': text})
  endif
  return segments
endfunction

function! s:BuildSegments(left, base, right)
  let dir = tempname()
  call mkdir(dir, 'p')
  let paths = []
  for [name, lines] in [['yours', a:left], ['base', a:base], ['theirs', a:right]]
    let path = dir.'/'.name
    call writefile(lines, path)
    call add(paths, shellescape(path))
  endfor
  let cmd = 'git merge-file -p --diff3 -L yours -L base -L theirs '.join(paths, ' ')
  " It exits with the number of conflicts
  let output = systemlist(cmd)
  call delete(dir, 'rf')
  let segments = s:ParseMergeOutput(output)
  call s:MarkAutoMerged(segments, a:left, a:base)
  return segments
endfunction

" Mark the lines git merged on its own, which changed on one side only:
" segment.auto maps a line index of a text segment to 'left', 'right' or
" 'both'. Diff the base with the merged text, the conflicts kept as base,
" then tell by yours whose change each one is
function! s:MarkAutoMerged(segments, left, base)
  let merged = []
  let starts = []
  for segment in a:segments
    call add(starts, len(merged) + 1)
    call extend(merged, segment.type == 'text' ? segment.lines : segment.base)
  endfor

  let yours = {}
  for hunk in s:DiffHunks(a:base, a:left)
    let yours[hunk.old] = hunk.lines
  endfor

  for hunk in s:DiffHunks(a:base, merged)
    if !has_key(yours, hunk.old)
      let side = 'right'
    else
      let side = yours[hunk.old] == hunk.lines ? 'left' : 'both'
    endif
    for lnum in range(hunk.start, hunk.start + len(hunk.lines) - 1)
      for idx in range(len(a:segments))
        let segment = a:segments[idx]
        let offset = lnum - starts[idx]
        if segment.type == 'text' && offset >= 0 && offset < len(segment.lines)
          if !has_key(segment, 'auto')
            let segment.auto = {}
          endif
          let segment.auto[offset] = side
        endif
      endfor
    endfor
  endfor
endfunction

" Hunks of changed lines from a:old to a:new: {'old': 'start,count' in
" a:old, 'start': first line in a:new, 'lines': the new lines}
function! s:DiffHunks(old, new)
  let dir = tempname()
  call mkdir(dir, 'p')
  call writefile(a:old, dir.'/old')
  call writefile(a:new, dir.'/new')
  let output = systemlist('git diff --no-index --no-color --no-ext-diff -U0 -- '
        \.shellescape(dir.'/old').' '.shellescape(dir.'/new'))
  call delete(dir, 'rf')

  let hunks = []
  for line in output
    let m = matchlist(line, '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)')
    if !empty(m)
      let num = empty(m[2]) ? 1 : str2nr(m[2])
      call add(hunks, {'old': m[1].','.num, 'start': str2nr(m[3]), 'lines': []})
    elseif !empty(hunks) && line[0] ==# '+'
      call add(hunks[-1].lines, line[1:])
    endif
  endfor
  return hunks
endfunction

function! s:Conflicts()
  return filter(copy(s:merge.segments), 'v:val.type == "conflict"')
endfunction

function! s:CountUnresolved()
  return len(filter(s:Conflicts(), 'empty(v:val.state)'))
endfunction

function! s:GetResultLines()
  let lines = []
  for segment in s:merge.segments
    call extend(lines, segment.type == 'text' ? segment.lines : segment.result)
  endfor
  return lines
endfunction

function! s:Choose(segment, state)
  let a:segment.state = a:state
  if a:state == 'left'
    let a:segment.result = copy(a:segment.left)
  elseif a:state == 'right'
    let a:segment.result = copy(a:segment.right)
  elseif a:state == 'both'
    let a:segment.result = a:segment.left + a:segment.right
  else
    let a:segment.result = []
  endif
endfunction

" ---------------------------------------------------------------- open

" Resolve a:file, relative to the project. The ones a side deleted are asked
" about instead, since there is nothing to merge line by line
function! project#git_merge#Open(file)
  let state = project#git_merge#GetState()
  let yours = s:ReadStage(a:file, get(state, 'yours', 2))
  let theirs = s:ReadStage(a:file, get(state, 'theirs', 3))
  if yours is v:null || theirs is v:null
    call s:ResolveDeleted(a:file, yours, theirs)
    return
  endif
  let base = s:ReadStage(a:file, 1)

  let [left_title, right_title] = s:GetTitles(state)
  let s:merge = {
        \'file': a:file,
        \'segments': s:BuildSegments(yours, base is v:null ? [] : base, theirs),
        \'left_title': left_title,
        \'right_title': right_title,
        \'state': state,
        \}
  call s:OpenWindows()
  call s:Render()
  call s:JumpToConflict(1, 1)
  if empty(s:Conflicts())
    call project#Info('No conflicting lines left, press '.s:GetMergeKey('finish').' to accept it')
  endif
endfunction

function! s:ResolveDeleted(file, yours, theirs)
  if a:yours is v:null && a:theirs is v:null
    let question = 'Both sides deleted '.a:file.'. d delete / k keep? '
  elseif a:yours is v:null
    let question = 'You deleted '.a:file.', they changed it. d delete / k keep theirs? '
  else
    let question = 'They deleted '.a:file.', you changed it. d delete / k keep yours? '
  endif

  redraw
  echo question
  let answer = nr2char(getchar())
  redraw
  let file = shellescape(a:file)
  if answer ==# 'd'
    call project#RunShellCmd('git rm -q -- '.file)
  elseif answer ==# 'k' && !(a:yours is v:null && a:theirs is v:null)
    let lines = a:yours is v:null ? a:theirs : a:yours
    call writefile(lines, $vim_project.'/'.a:file)
    call project#RunShellCmd('git add -- '.file)
  else
    return
  endif
  if !v:shell_error
    call s:OnFileResolved()
  endif
endfunction

function! s:OpenWindows()
  if bufwinnr(s:result_buffer) != -1
    execute bufwinnr(s:result_buffer).'wincmd w'
    return
  endif

  tabnew
  call s:SetupPane(s:left_buffer)
  rightbelow vnew
  call s:SetupPane(s:result_buffer)
  rightbelow vnew
  call s:SetupPane(s:right_buffer)
  call s:OpenHelp()
  wincmd =
  execute bufwinnr(s:result_buffer).'wincmd w'
endfunction

" The keys at the bottom, always in sight
function! s:OpenHelp()
  let mappings = project#config#Get('git_merge_mappings')
  let rows = [
        \[['take_yours', 'take yours'], ['take_theirs', 'take theirs'],
        \ ['take_both', 'take both'], ['edit', 'edit by hand'], ['undo', 'undo']],
        \[['next', 'next conflict'], ['previous', 'prev conflict'],
        \ ['all_yours', 'all yours'], ['all_theirs', 'all theirs'],
        \ ['finish', 'accept, git add'], ['quit', 'discard choices']],
        \]
  " Each key is highlighted by its position, labels may hold any word
  let lines = []
  let positions = []
  for row in rows
    let line = ' '
    for [name, label] in row
      let key = s:GetHelpKey(mappings, name)
      if empty(key)
        continue
      endif
      call add(positions, [len(lines) + 1, len(line) + 1, len(key)])
      let line .= printf('%-3s %-16s ', key, label)
    endfor
    call add(lines, substitute(line, '\s\+$', '', ''))
  endfor

  botright 2new
  silent execute 'file' s:help_buffer
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nowrap nonumber nocursorline signcolumn=no winfixheight
  call setline(1, lines)
  setlocal nomodifiable
  setlocal statusline=\ Keys
  hi default link ProjectMergeKey Special
  call matchaddpos('ProjectMergeKey', positions, 10)
endfunction

function! s:SetupPane(name)
  silent execute 'file' a:name
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nomodifiable nowrap nonumber nofoldenable
  setlocal scrollbind cursorbind cursorline signcolumn=yes
  silent! execute 'doautocmd filetypedetect BufRead' fnameescape(s:merge.file)

  let mappings = project#config#Get('git_merge_mappings')
  call s:AddMapping(mappings.take_yours, 'Take("left")')
  call s:AddMapping(mappings.take_theirs, 'Take("right")')
  call s:AddMapping(mappings.take_both, 'Take("both")')
  call s:AddMapping(mappings.undo, 'Take("")')
  call s:AddMapping(mappings.edit, 'EditConflict()')
  call s:AddMapping(mappings.next, 'JumpToConflict(1, 0)')
  call s:AddMapping(mappings.previous, 'JumpToConflict(-1, 0)')
  call s:AddMapping(mappings.all_yours, 'TakeAll("left")')
  call s:AddMapping(mappings.all_theirs, 'TakeAll("right")')
  call s:AddMapping(mappings.finish, 'Finish()')
  call s:AddMapping(mappings.quit, 'Quit()')

  " The conflict number follows the cursor
  autocmd CursorMoved <buffer> call s:UpdateStatusLines()
endfunction

function! s:IsMapped(key)
  return !empty(a:key) && a:key !=? '<NOP>'
endfunction

" Like 'q to accept, Q to discard', with the configured keys
function! s:AcceptDiscardHint()
  let hints = []
  for [name, label] in [['finish', 'accept'], ['quit', 'discard']]
    let key = s:GetMergeKey(name)
    if !empty(key)
      call add(hints, key.' to '.label)
    endif
  endfor
  return join(hints, ', ')
endfunction

" Key of a:name in the merge window, '' when it has none
function! s:GetMergeKey(name)
  return s:GetHelpKey(project#config#Get('git_merge_mappings'), a:name)
endfunction

function! s:GetHelpKey(mappings, name)
  let key = get(a:mappings, a:name, '')
  return s:IsMapped(key) ? key : ''
endfunction

function! s:AddMapping(key, call)
  if !s:IsMapped(a:key)
    return
  endif
  let key = a:key == '<' ? '<lt>' : a:key
  execute 'nnoremap <buffer><silent><nowait> '.key.' :<C-u>call <SID>'.a:call.'<CR>'
endfunction

" ---------------------------------------------------------------- render

function! s:DefineHighlights()
  hi default ProjectMergeUnresolved ctermbg=52 guibg=#5f0000
  hi default ProjectMergeResolved ctermbg=22 guibg=#1f3f1f
  hi default ProjectMergeManual ctermbg=17 guibg=#1f2f4f
  hi default ProjectMergePending ctermbg=58 guibg=#4f4000
  hi default link ProjectMergeUnused Comment
  hi default link ProjectMergeFiller NonText
  hi default link ProjectMergeAuto Comment

  let utf8 = &encoding ==# 'utf-8'
  let signs = {
        \'unresolved': ['??', 'ProjectMergeUnresolved'],
        \'resolved': [utf8 ? '✓' : 'ok', 'ProjectMergeResolved'],
        \'manual': [utf8 ? '✎' : '~~', 'ProjectMergeManual'],
        \'pending_left': ['<', 'ProjectMergePending'],
        \'pending_right': ['>', 'ProjectMergePending'],
        \'used': [utf8 ? '✓' : 'ok', 'ProjectMergeResolved'],
        \'unused': ['--', 'ProjectMergeUnused'],
        \'filler': [' ', 'ProjectMergeFiller'],
        \'auto_left': [utf8 ? '◂' : '<~', 'ProjectMergeAuto'],
        \'auto_right': [utf8 ? '▸' : '~>', 'ProjectMergeAuto'],
        \'auto_both': [utf8 ? '◆' : '<>', 'ProjectMergeAuto'],
        \}
  for [name, value] in items(signs)
    call sign_define('ProjectMerge_'.name, {'text': value[0], 'linehl': value[1], 'texthl': value[1]})
  endfor
endfunction

" Sign names of a conflict in the left, middle and right panes
function! s:GetConflictSigns(segment)
  let state = a:segment.state
  if empty(state)
    return ['pending_left', 'unresolved', 'pending_right']
  elseif state == 'manual'
    return ['unused', 'manual', 'unused']
  endif
  let left = state == 'left' || state == 'both' ? 'used' : 'unused'
  let right = state == 'right' || state == 'both' ? 'used' : 'unused'
  return [left, 'resolved', right]
endfunction

function! s:Render()
  call s:DefineHighlights()
  let panes = [[], [], []]
  let signs = [[], [], []]
  let s:layout = []

  for segment in s:merge.segments
    let start = len(panes[0]) + 1
    if segment.type == 'text'
      for pane in panes
        call extend(pane, segment.lines)
      endfor
      " Merged by git: grey in the result and on the side it came from
      for [offset, side] in items(get(segment, 'auto', {}))
        let lnum = start + offset
        call add(signs[1], [lnum, 'auto_'.side])
        if side != 'right'
          call add(signs[0], [lnum, 'auto_'.side])
        endif
        if side != 'left'
          call add(signs[2], [lnum, 'auto_'.side])
        endif
      endfor
      call add(s:layout, {'start': start, 'height': len(segment.lines)})
      continue
    endif

    let result = empty(segment.state) ? [s:unresolved_text] : segment.result
    let contents = [segment.left, result, segment.right]
    let height = max([1, len(segment.left), len(result), len(segment.right)])
    let names = s:GetConflictSigns(segment)
    for idx in range(3)
      let lines = contents[idx]
      call extend(panes[idx], lines + repeat([''], height - len(lines)))
      for offset in range(height)
        let name = offset < len(lines) ? names[idx] : 'filler'
        call add(signs[idx], [start + offset, name])
      endfor
    endfor
    call add(s:layout, {'start': start, 'height': height})
  endfor

  let buffers = [s:left_buffer, s:result_buffer, s:right_buffer]
  for idx in range(3)
    let buf = bufnr(buffers[idx])
    call setbufvar(buf, '&modifiable', 1)
    silent call deletebufline(buf, 1, '$')
    call setbufline(buf, 1, panes[idx])
    call setbufvar(buf, '&modifiable', 0)
    call sign_unplace('ProjectMerge', {'buffer': buf})
    for [lnum, name] in signs[idx]
      call sign_place(0, 'ProjectMerge', 'ProjectMerge_'.name, buf, {'lnum': lnum})
    endfor
  endfor
  call s:UpdateStatusLines()
endfunction

function! s:UpdateStatusLines()
  if empty(s:merge)
    return
  endif
  let total = len(s:Conflicts())
  let current = s:GetConflictNumber()
  let unresolved = s:CountUnresolved()
  " Shorten the file name first when the pane is narrow
  if unresolved
    let status = printf(' %s/%d  %d unresolved  %%<%s', current ? current : '-', total,
          \unresolved, s:EscapeStatus(s:merge.file))
  else
    " Short enough for a narrow pane: what to press matters more here
    let status = ' done: '.s:AcceptDiscardHint().'  %<'.s:EscapeStatus(s:merge.file)
  endif
  call s:SetStatusLine(s:left_buffer, ' '.s:EscapeStatus(s:merge.left_title))
  call s:SetStatusLine(s:result_buffer, status)
  call s:SetStatusLine(s:right_buffer, ' '.s:EscapeStatus(s:merge.right_title))
endfunction

function! s:EscapeStatus(text)
  return substitute(a:text, '%', '%%', 'g')
endfunction

function! s:SetStatusLine(name, text)
  let winnr = bufwinnr(a:name)
  if winnr != -1
    call setwinvar(winnr, '&statusline', a:text)
  endif
endfunction

" ---------------------------------------------------------------- actions

" Index of the segment at a:lnum
function! s:GetSegmentIndex(lnum)
  for idx in range(len(s:layout))
    let item = s:layout[idx]
    if a:lnum >= item.start && a:lnum < item.start + max([1, item.height])
      return idx
    endif
  endfor
  return -1
endfunction

function! s:GetCurrentConflict()
  let idx = s:GetSegmentIndex(line('.'))
  if idx == -1 || s:merge.segments[idx].type != 'conflict'
    return -1
  endif
  return idx
endfunction

" 1-based number of the conflict under the cursor, 0 if none
function! s:GetConflictNumber()
  let idx = s:GetCurrentConflict()
  if idx == -1
    return 0
  endif
  return len(filter(s:merge.segments[: idx], 'v:val.type == "conflict"'))
endfunction

function! s:CursorTo(idx)
  call cursor(s:layout[a:idx].start, 1)
  normal! zz
  call s:UpdateStatusLines()
endfunction

" Move to the next (a:direction 1) or previous (-1) conflict. With
" a:unresolved, only to unresolved ones, starting from the cursor itself
function! s:JumpToConflict(direction, unresolved)
  let total = len(s:merge.segments)
  if !total
    return 0
  endif
  let current = s:GetSegmentIndex(line('.'))
  let idx = a:unresolved && current != -1 ? current : current + a:direction
  for _ in range(total)
    let idx = (idx + total) % total
    let segment = s:merge.segments[idx]
    if segment.type == 'conflict' && (!a:unresolved || empty(segment.state))
      call s:CursorTo(idx)
      return 1
    endif
    let idx += a:direction
  endfor
  call s:UpdateStatusLines()
  return 0
endfunction

" Apply a:state to the conflict under the cursor, then go to the next
" unresolved one. Off a conflict, only move to the next one so nothing is
" changed by accident
function! s:Take(state)
  let idx = s:GetCurrentConflict()
  if idx == -1
    if s:JumpToConflict(1, 0)
      call project#Info('Moved to the next conflict, press the key again to apply')
    endif
    return
  endif

  call s:Choose(s:merge.segments[idx], a:state)
  call s:Render()
  call s:CursorTo(idx)
  if !empty(a:state) && !s:JumpToConflict(1, 1)
    call project#Info('All conflicts resolved, '.s:AcceptDiscardHint())
  endif
endfunction

function! s:TakeAll(state)
  let name = a:state == 'left' ? 'yours' : 'theirs'
  redraw
  echo 'Take '.name.' for all conflicts? (y/n) '
  let answer = nr2char(getchar())
  redraw
  if answer !=# 'y'
    return
  endif
  for segment in s:Conflicts()
    call s:Choose(segment, a:state)
  endfor
  call s:Render()
  call s:UpdateStatusLines()
endfunction

" Edit the result of the current conflict in a split, :w saves it back
function! s:EditConflict()
  let idx = s:GetCurrentConflict()
  if idx == -1
    call s:JumpToConflict(1, 0)
    return
  endif
  let segment = s:merge.segments[idx]
  let lines = empty(segment.state) ? segment.left + segment.right : segment.result

  " Full width, above the keys
  execute bufwinnr(s:help_buffer).'wincmd w'
  aboveleft new
  silent execute 'file' s:edit_buffer
  setlocal buftype=acwrite bufhidden=wipe noswapfile nobuflisted
  call setline(1, lines)
  setlocal nomodified
  let b:vim_project_merge_segment = idx
  " The same keys as the merge window: accept or discard, :w and :q! work too
  let accept = s:GetMergeKey('finish')
  let discard = s:GetMergeKey('quit')
  let hints = []
  if !empty(accept)
    execute 'nnoremap <buffer><silent><nowait> '.accept.' :<C-u>silent write<CR>'
    call add(hints, accept.' to accept')
  endif
  if !empty(discard)
    execute 'nnoremap <buffer><silent><nowait> '.discard.' :<C-u>bwipeout!<CR>'
    call add(hints, discard.' to discard')
  endif
  let &l:statusline = ' Edit the conflict'
        \.(empty(hints) ? ', :w to use it, :q! to cancel' : ', '.join(hints, ', '))
  autocmd BufWriteCmd <buffer> call s:SaveEditedConflict()
  " Back to the result however it is closed: :w, :wq, :x or :q!
  autocmd BufWipeout <buffer> call timer_start(0, {-> s:BackToResult()})
endfunction

function! s:SaveEditedConflict()
  let idx = b:vim_project_merge_segment
  let segment = s:merge.segments[idx]
  let segment.state = 'manual'
  let segment.result = getline(1, '$')
  if segment.result == ['']
    let segment.result = []
  endif
  setlocal nomodified
  " Close it once the write is done. Closing it here would let the q of
  " :wq or :x close the window below it, the result
  call timer_start(0, {-> s:CloseEdit(idx)})
endfunction

function! s:CloseEdit(idx)
  if bufexists(s:edit_buffer)
    silent! execute 'bwipeout!' bufnr(s:edit_buffer)
  endif
  if !s:BackToResult()
    return
  endif
  call s:Render()
  call s:CursorTo(a:idx)
  call s:JumpToConflict(1, 1)
endfunction

function! s:BackToResult()
  let winnr = bufwinnr(s:result_buffer)
  if winnr == -1 || empty(s:merge)
    return 0
  endif
  execute winnr.'wincmd w'
  return 1
endfunction

" Write the result, git add it, then go back to the local changes
function! s:Finish()
  let unresolved = s:CountUnresolved()
  if unresolved
    call s:JumpToConflict(1, 1)
    let quit = s:GetMergeKey('quit')
    call project#Warn(unresolved.' conflicts left unresolved'
          \.(s:IsMapped(quit) ? ', '.quit.' to discard the choices' : ''))
    return
  endif

  let path = $vim_project.'/'.s:merge.file
  call writefile(s:GetResultLines(), path)
  let file = shellescape(s:merge.file)
  call project#RunShellCmd('git add -- '.file)
  if v:shell_error
    return
  endif
  let state = s:merge.state
  if get(state, 'name', '') == 'stash'
    " Back to a local change, as applying the stash without conflicts would
    call project#RunShellCmd('git reset -q -- '.file)
  endif
  let bufnr = bufnr(path)
  if bufnr != -1
    silent! execute 'checktime' bufnr
  endif

  call s:CloseWindows()
  call s:OnFileResolved(state)
endfunction

function! s:Quit()
  let touched = len(filter(s:Conflicts(), '!empty(v:val.state)'))
  if touched
    redraw
    echo 'Discard the choices of '.touched.' conflicts? (y/n) '
    let answer = nr2char(getchar())
    redraw
    if answer !=# 'y'
      return
    endif
  endif
  call s:CloseWindows()
endfunction

function! s:CloseWindows()
  for name in [s:edit_buffer, s:help_buffer, s:left_buffer, s:result_buffer, s:right_buffer]
    if bufexists(name)
      silent! execute 'bwipeout!' bufnr(name)
    endif
  endfor
  let s:merge = {}
  let s:layout = []
endfunction

" Back to the local changes. Once no file is left, offer to finish what git
" is in the middle of
" a:1: the state the file was resolved in
function! s:OnFileResolved(...)
  call project#git#Status()
  if !empty(project#git_merge#GetUnmergedFiles())
    call project#Info('Resolved. Press '.s:GetKey('open_changelist_or_file').' on the next conflicting file')
    return
  endif
  if get(get(a:000, 0, {}), 'name', '') == 'stash'
    call project#Info('All conflicts resolved. Your changes are still in the stash too: '
          \.'git stash drop once you are sure')
    return
  endif

  let state = project#git_merge#GetState()
  if empty(state)
    call project#Info('All conflicts resolved')
    return
  endif
  redraw
  echo 'All conflicts resolved. Continue the '.state.name.'? (y/n) '
  let answer = nr2char(getchar())
  redraw
  if answer ==# 'y'
    call project#git_merge#Continue(state)
  endif
endfunction

function! project#git_merge#Continue(state)
  let output = project#RunShellCmd(a:state.continue)
  if !v:shell_error
    call project#git#Status()
    if !empty(project#git_merge#GetUnmergedFiles())
      " A rebase may stop at the next commit with new conflicts
      call project#Warn('New conflicts, press '.s:GetKey('open_changelist_or_file').' on a file to resolve it')
    else
      call project#Info('Finished the '.a:state.name)
    endif
  endif
endfunction

" Abort the merge, rebase, ... once confirmed
function! project#git_merge#Abort()
  let state = project#git_merge#GetState()
  if empty(state)
    call project#Info('No merge, rebase, cherry-pick or revert in progress')
    return
  endif
  if !has_key(state, 'abort')
    call project#Info('Applying the stash has conflicts. Your changes are safe in it: '
          \.'resolve them, or git checkout the files and git stash pop again later')
    return
  endif
  redraw
  echo 'Abort the '.state.name.' and go back to before it? (y/n) '
  let answer = nr2char(getchar())
  redraw
  if answer !=# 'y'
    return
  endif
  call project#RunShellCmd(state.abort)
  if !v:shell_error
    call project#git#Status()
    call project#Info('Aborted the '.state.name)
  endif
endfunction

" After a failed pull or merge: show the conflicting files if there are any.
" Return whether there were
function! project#git_merge#ShowConflicts()
  let files = project#git_merge#GetUnmergedFiles()
  if empty(files)
    return 0
  endif
  call project#git#Status()
  call search('^\S*\s*Unmerged', 'w')
  redraw
  call project#Warn('Merge conflicts in '.len(files).' files. Press '
        \.s:GetKey('open_changelist_or_file').' on a file to resolve it, '
        \.s:GetKey('abort_merge').' to abort')
  return 1
endfunction

" Key of a:name in the local changes, as it reads in a message
function! s:GetKey(name)
  let key = get(project#config#Get('git_local_changes_mappings'), a:name, '')
  return key == "\<cr>" ? 'Enter' : key
endfunction
