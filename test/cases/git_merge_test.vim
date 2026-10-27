" Tests of the merge window: resolving conflicts in yours | result | theirs
let s:file = 'autoload/project/git_merge.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

function! s:Git(repo, args)
  return system('git -C '.shellescape(a:repo).' '.a:args)
endfunction

" A project in the middle of merging 'feature', which conflicts with the
" current branch on lines 2 and 4 of file.txt
function! s:OpenConflict(name)
  let base = Helper_TmpDir(a:name)
  let repo = base.'/proj'
  call mkdir(repo, 'p')
  call writefile(['a', 'b', 'c', 'd', 'e'], repo.'/file.txt')
  call s:Git(repo, 'init -q')
  call s:Git(repo, 'config user.name t')
  call s:Git(repo, 'config user.email t@t')
  call s:Git(repo, 'add .')
  call s:Git(repo, 'commit -q -m init')
  call s:Git(repo, 'checkout -q -b feature')
  call writefile(['a', 'B theirs', 'c', 'D theirs', 'e'], repo.'/file.txt')
  call s:Git(repo, 'commit -q -am feature')
  call s:Git(repo, 'checkout -q -')
  call writefile(['a', 'B yours', 'c', 'D yours', 'e'], repo.'/file.txt')
  call s:Git(repo, 'commit -q -am mine')
  call s:Git(repo, 'merge feature')

  let project = {'name': 'proj', 'path': base, 'fullpath': repo, 'note': '', 'option': {}}
  call Helper_Call('autoload/project.vim', 'InitProjectConfig', [project])
  call project#OpenProject(project)
  return repo
endfunction

function! s:Close(repo)
  call s:Git(a:repo, 'merge --abort')
  silent! call s:Call('CloseWindows')
  silent! execute 'bwipeout!' bufnr('local_changes')
  call project#QuitProject()
  silent! tabonly!
  silent! %bwipeout!
  " The headless screen is small, four windows squeeze the command line
  set cmdheight=1
endfunction

function! s:Lines(name)
  return getbufline(bufnr(a:name), 1, '$')
endfunction

function! Test_ParseMergeOutput()
  let segments = s:Call('ParseMergeOutput', ['a', '<<<<<<< yours', 'x',
        \'||||||| base', 'o', '=======', 'y', 'z', '>>>>>>> theirs', 'b'])
  call assert_equal(3, len(segments))
  call assert_equal(['a'], segments[0].lines)
  call assert_equal(['x'], segments[1].left)
  call assert_equal(['o'], segments[1].base)
  call assert_equal(['y', 'z'], segments[1].right)
  call assert_equal(['b'], segments[2].lines)
endfunction

function! Test_merge_state_and_unmerged_status()
  let repo = s:OpenConflict('merge state')
  try
    call assert_equal('merge', project#git_merge#GetState().name)
    call assert_equal(['file.txt'], project#git_merge#GetUnmergedFiles())
    call project#git#Status()
    call assert_equal(['U file.txt'], Helper_ScriptVar('autoload/project/git.vim', 'unmerged_files'))
  finally
    call s:Close(repo)
  endtry
endfunction

function! Test_resolve_conflicts_in_merge_window()
  let repo = s:OpenConflict('merge window')
  try
    call project#git_merge#Open('file.txt')
    call assert_equal('vim_project_merge_result', bufname('%'))
    " Panes line up, the cursor is on the first conflict
    call assert_equal(['a', 'B yours', 'c', 'D yours', 'e'], s:Lines('vim_project_merge_yours'))
    call assert_equal(['a', 'B theirs', 'c', 'D theirs', 'e'], s:Lines('vim_project_merge_theirs'))
    call assert_equal(2, line('.'))
    " The keys stay in sight at the bottom
    call Helper_AssertContains(join(s:Lines('vim_project_merge_keys')), '<   take yours')
    call Helper_AssertContains(join(s:Lines('vim_project_merge_keys')), 'w   accept, git add')
    call assert_equal('(unresolved)', getline(2))

    " Finishing with conflicts left keeps the window
    normal w
    call assert_equal('vim_project_merge_result', bufname('%'))

    " Take yours, then the cursor moves to the next conflict: take theirs
    normal <
    call assert_equal('B yours', getline(2))
    call assert_equal(4, line('.'))
    normal >
    call assert_equal('D theirs', getline(4))

    " Undo it, and take both instead: the conflict grows, panes still align
    normal u
    call assert_equal('(unresolved)', getline(4))
    normal =
    call assert_equal(['a', 'B yours', 'c', 'D yours', 'D theirs', 'e'], s:Lines('vim_project_merge_result'))
    call assert_equal(['a', 'B yours', 'c', 'D yours', '', 'e'], s:Lines('vim_project_merge_yours'))

    " Finish: written, added, back to the local changes. Don't continue yet
    call feedkeys('wn', 'xt')
    call assert_equal(['a', 'B yours', 'c', 'D yours', 'D theirs', 'e'], readfile(repo.'/file.txt'))
    call assert_equal(-1, bufwinnr('vim_project_merge_result'))
    call assert_equal([], project#git_merge#GetUnmergedFiles())
    call assert_equal('merge', project#git_merge#GetState().name)
  finally
    call s:Close(repo)
  endtry
endfunction

function! Test_finish_continues_the_merge()
  let repo = s:OpenConflict('merge continue')
  try
    call project#git_merge#Open('file.txt')
    " :normal ends its keys with <Esc>, feed the answers with them instead
    call feedkeys('Ry', 'xt')
    call assert_equal(['a', 'B theirs', 'c', 'D theirs', 'e'], s:Call('GetResultLines'))
    call feedkeys('wy', 'xt')
    call assert_equal({}, project#git_merge#GetState())
    call assert_match('Merge', s:Git(repo, 'log -1 --format=%s'))
  finally
    call s:Close(repo)
  endtry
endfunction

function! Test_edit_conflict_by_hand()
  let repo = s:OpenConflict('merge edit')
  try
    call project#git_merge#Open('file.txt')
    normal e
    call assert_equal('vim_project_merge_edit', bufname('%'))
    call setline(1, ['B mixed', 'B more'])
    silent write
    " The edit window closes once the write is done
    sleep 50m
    call assert_equal('vim_project_merge_result', bufname('%'))
    call assert_equal(['B mixed', 'B more'], getline(2, 3))
    call assert_equal('manual', s:Call('Conflicts')[0].state)

    " :wq and :q! close only the edit window, never the result
    for cmd in ['wq', 'x', 'q!']
      call cursor(5, 1)
      normal e
      call assert_equal('vim_project_merge_edit', bufname('%'))
      silent execute cmd
      sleep 50m
      call assert_equal('vim_project_merge_result', bufname('%'), cmd)
      call assert_notequal(-1, bufwinnr('vim_project_merge_yours'), cmd)
      call assert_notequal(-1, bufwinnr('vim_project_merge_theirs'), cmd)
    endfor
  finally
    call s:Close(repo)
  endtry
endfunction

function! Test_abort_merge()
  let repo = s:OpenConflict('merge abort')
  try
    call feedkeys('y', 't')
    call project#git_merge#Abort()
    call assert_equal({}, project#git_merge#GetState())
    call assert_equal(['a', 'B yours', 'c', 'D yours', 'e'], readfile(repo.'/file.txt'))
  finally
    call s:Close(repo)
  endtry
endfunction
