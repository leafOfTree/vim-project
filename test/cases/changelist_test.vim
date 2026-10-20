" Tests for the git local changes buffer (:ProjectGitStatus): rolling back,
" shelving and unshelving files, and moving them between changelists. They
" run on a real repository, through the buffer lines like a user would.
let s:file = 'autoload/project/git.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

" Call a function defined with 'range' on lines a:first to a:last
function! s:RangeCall(name, first, last)
  execute a:first.','.a:last.'call '.printf('<SNR>%d_%s()', Helper_Sid(s:file), a:name)
endfunction

function! s:Changelist()
  return Helper_ScriptVar(s:file, 'changelist')
endfunction

function! s:FolderFiles(name)
  for folder in s:Changelist()
    if folder.name ==# a:name
      return sort(copy(folder.files))
    endif
  endfor
  return v:null
endfunction

" A project with tracked.txt, other.txt and sub/deep.txt committed
function! s:OpenRepo(name)
  let base = Helper_TmpDir(a:name)
  let repo = base.'/proj'
  call mkdir(repo.'/sub', 'p')
  call writefile(['one'], repo.'/tracked.txt')
  call writefile(['two'], repo.'/other.txt')
  call writefile(['three'], repo.'/sub/deep.txt')
  let git = 'git -C '.shellescape(repo)
  call system(git.' init -q && '.git.' config user.name t && '.git.' config user.email t@t'
        \.' && '.git.' add . && '.git.' commit -q -m init')
  let project = {'name': 'proj', 'path': base, 'fullpath': repo, 'note': '', 'option': {}}
  call Helper_Call('autoload/project.vim', 'InitProjectConfig', [project])
  call project#OpenProject(project)
  return repo
endfunction

function! s:CloseRepo()
  silent! execute 'bwipeout!' bufnr('local_changes')
  call project#QuitProject()
  silent! %bwipeout!
endfunction

" Line of the changes buffer matching a:pattern, which must exist
function! s:Line(pattern)
  let lnum = search(a:pattern, 'nw')
  call assert_true(lnum > 0, 'no line matches '.a:pattern.' in '.string(getline(1, '$')))
  return lnum
endfunction

function! s:HasLine(pattern)
  return search(a:pattern, 'nw') > 0
endfunction

function! s:ExpandFolder(name)
  call cursor(s:Line('|'.a:name.' '), 1)
  call s:Call('OpenFolderOrFile')
endfunction

" ---------------------------------------------------------------- rollback

function! Test_RollbackFile()
  let repo = s:OpenRepo('rollback')
  try
    call writefile(['changed'], repo.'/tracked.txt')
    call writefile(['changed'], repo.'/other.txt')
    call writefile(['changed'], repo.'/sub/deep.txt')
    call writefile(['new'], repo.'/new.txt')
    call project#git#Status()

    " 'n' keeps the change
    let lnum = s:Line('|tracked\.txt|')
    call feedkeys('n', 't')
    call s:RangeCall('RollbackFile', lnum, lnum)
    call assert_equal(['changed'], readfile(repo.'/tracked.txt'))

    " 'y' restores a tracked file and updates the list
    call feedkeys('y', 't')
    call s:RangeCall('RollbackFile', lnum, lnum)
    call assert_equal(['one'], readfile(repo.'/tracked.txt'))
    call assert_false(s:HasLine('|tracked\.txt|'))

    " An untracked file is removed
    call s:ExpandFolder('Untracked')
    let lnum = s:Line('|new\.txt|')
    call feedkeys('y', 't')
    call s:RangeCall('RollbackFile', lnum, lnum)
    call assert_false(filereadable(repo.'/new.txt'))

    " A range rolls back every file in it
    let first = s:Line('|deep\.txt|')
    let last = s:Line('|other\.txt|')
    call feedkeys('y', 't')
    call s:RangeCall('RollbackFile', min([first, last]), max([first, last]))
    call assert_equal(['two'], readfile(repo.'/other.txt'))
    call assert_equal(['three'], readfile(repo.'/sub/deep.txt'))
    call assert_equal('', system('git -C '.shellescape(repo).' status --porcelain'))
  finally
    call s:CloseRepo()
  endtry
endfunction

" ---------------------------------------------------------------- shelf

function! s:Shelve(pattern)
  let lnum = s:Line(a:pattern)
  call feedkeys("work\<CR>", 't')
  call s:RangeCall('ShelfFile', lnum, lnum)
endfunction

" Shelving saves the changes as a patch and reverts them, like IntelliJ;
" unshelving applies the patch again
function! Test_ShelfFile_and_UnshelfFile()
  let repo = s:OpenRepo('shelf')
  let git = 'git -C '.shellescape(repo)
  try
    " Bytes 00 01 02 03: NUL is written as "\n" (Neovim 0.5.0 has no blob writefile())
    call writefile(["\n\x01\x02\x03"], repo.'/bin.dat', 'b')
    call system(git.' add bin.dat && '.git.' commit -q -m bin')

    call writefile(['shelved change'], repo.'/tracked.txt')
    call writefile(['deep change'], repo.'/sub/deep.txt')
    call writefile(['staged'], repo.'/other.txt')
    call system(git.' add other.txt')
    call writefile(['staged', 'unstaged'], repo.'/other.txt')
    call writefile(["\xff\n\xff"], repo.'/bin.dat', 'b')
    call writefile(['brand new'], repo.'/new.txt')
    call project#git#Status()

    for pattern in ['|tracked\.txt|', '|deep\.txt|', '|bin\.dat|']
      call s:Shelve(pattern)
    endfor
    " A file with staged and unstaged changes is listed under Staged
    call s:ExpandFolder('Staged')
    call s:Shelve('|other\.txt|')
    call s:ExpandFolder('Untracked')
    call s:Shelve('|new\.txt|')

    " Every change is reverted, staged or not, and the new file removed
    call assert_equal('', system(git.' status --porcelain'))
    call assert_equal(['one'], readfile(repo.'/tracked.txt'))
    call assert_false(filereadable(repo.'/new.txt'))

    " ... and kept in the patches
    let shelf = $vim_project_config.'/shelf/work'
    call assert_equal(['bin.dat.diff', 'new.txt.diff', 'other.txt.diff', 'sub+deep.txt.diff', 'tracked.txt.diff'],
          \ s:FolderFiles('work'))
    call assert_match('+shelved change', join(readfile(shelf.'/tracked.txt.diff'), "\n"))
    call assert_match('+staged\n+unstaged', join(readfile(shelf.'/other.txt.diff'), "\n"))
    call assert_match('+brand new', join(readfile(shelf.'/new.txt.diff'), "\n"))
    call assert_match('GIT binary patch', join(readfile(shelf.'/bin.dat.diff'), "\n"))

    " Unshelve the whole shelf from its line
    call project#git#Status()
    let lnum = s:Line('|work ')
    call s:RangeCall('UnshelfFile', lnum, lnum)
    call assert_equal(['shelved change'], readfile(repo.'/tracked.txt'))
    call assert_equal(['deep change'], readfile(repo.'/sub/deep.txt'))
    call assert_equal(['staged', 'unstaged'], readfile(repo.'/other.txt'))
    call assert_equal(["\xff\n\xff"], readfile(repo.'/bin.dat', 'b'))
    call assert_equal(['brand new'], readfile(repo.'/new.txt'))

    " Unshelve a single file of the shelf
    call system(git.' restore --source=HEAD --staged --worktree . && '.git.' clean -fdq')
    call project#git#Status()
    call s:ExpandFolder('work')
    let lnum = s:Line('|deep\.txt\.diff| sub')
    call s:RangeCall('UnshelfFile', lnum, lnum)
    call assert_equal(['deep change'], readfile(repo.'/sub/deep.txt'))
    call assert_equal(['one'], readfile(repo.'/tracked.txt'))
  finally
    call s:CloseRepo()
  endtry
endfunction

" ---------------------------------------------------------------- commit

" Commit a file from its line: the message window commits when closed
function! Test_Commit_from_message_window()
  let repo = s:OpenRepo('commit')
  let git = 'git -C '.shellescape(repo)
  try
    call writefile(['changed'], repo.'/tracked.txt')
    call writefile(['changed'], repo.'/other.txt')
    call project#git#Status()

    let lnum = s:Line('|tracked\.txt|')
    call s:RangeCall('Commit', lnum, lnum)
    call assert_equal('gitcommit', &filetype)
    call append(0, 'from window')
    quit
    call assert_equal('from window', trim(system(git.' log -1 --pretty=%s')))
    call assert_equal(['tracked.txt'],
          \ split(system(git.' show --name-only --pretty=format: HEAD'), "\n"))
    call assert_equal(['other.txt'], split(system(git.' diff --name-only'), "\n"))
  finally
    call s:CloseRepo()
  endtry
endfunction

" ---------------------------------------------------------------- move

function! Test_MoveToFolder()
  let repo = s:OpenRepo('move')
  try
    call writefile(['changed'], repo.'/tracked.txt')
    call writefile(['changed'], repo.'/other.txt')
    call project#git#Status()

    " A file goes to a new changelist, shown with its own line
    let lnum = s:Line('|tracked\.txt|')
    call feedkeys("feature\<CR>", 't')
    call s:RangeCall('MoveToFolder', lnum, lnum)
    call assert_equal(['tracked.txt'], s:FolderFiles('feature'))
    call assert_true(s:HasLine('|feature '))

    " Another file joins it
    let lnum = s:Line('|other\.txt|')
    call feedkeys("feature\<CR>", 't')
    call s:RangeCall('MoveToFolder', lnum, lnum)
    call assert_equal(['other.txt', 'tracked.txt'], s:FolderFiles('feature'))
    call assert_equal([], s:FolderFiles('Default'))

    " Staged is not a target
    let lnum = s:Line('|other\.txt|')
    call feedkeys("Staged\<CR>", 't')
    call s:RangeCall('MoveToFolder', lnum, lnum)
    call assert_equal(['other.txt', 'tracked.txt'], s:FolderFiles('feature'))

    " Moving the changelist line moves all of its files
    let lnum = s:Line('|feature ')
    call feedkeys("release\<CR>", 't')
    call s:RangeCall('MoveToFolder', lnum, lnum)
    call assert_equal(['other.txt', 'tracked.txt'], s:FolderFiles('release'))
    call assert_equal([], s:FolderFiles('feature'))

    " Changelists are saved when the buffer closes
    let file = $vim_project_config.'/changelist.json'
    execute 'bwipeout!' bufnr('local_changes')
    call assert_match('"release"', join(readfile(file), ''))
  finally
    call s:CloseRepo()
  endtry
endfunction

" ---------------------------------------------------------------- shelf messages

function! s:Messages(Fn)
  messages clear
  call a:Fn()
  return execute('messages')
endfunction

function! Test_shelf_lines_are_checked_with_clear_messages()
  let repo = s:OpenRepo('shelf messages')
  try
    call writefile(['shelved change'], repo.'/tracked.txt')
    call writefile(['new'], repo.'/new.txt')
    call project#git#Status()
    call s:Shelve('|tracked\.txt|')
    call s:ExpandFolder('Untracked')

    " Unshelve on a file outside a shelf: say so, do not run git
    let lnum = s:Line('|new\.txt|')
    let messages = s:Messages({-> s:RangeCall('UnshelfFile', lnum, lnum)})
    call assert_match('Unshelve works on a shelf .* This line is in \[Untracked\]', messages)
    call assert_notmatch('git apply\|E\d\+:', messages)

    " ... or on a changelist that is not a shelf
    let lnum = s:Line('|Default ')
    let messages = s:Messages({-> s:RangeCall('UnshelfFile', lnum, lnum)})
    call assert_match('This line is in \[Default\]', messages)

    " Shelving a shelved file again
    call s:ExpandFolder('work')
    let lnum = s:Line('|tracked\.txt\.diff|')
    let messages = s:Messages({-> s:RangeCall('ShelfFile', lnum, lnum)})
    call assert_match('Already shelved', messages)

    " A patch that conflicts with the current file: nothing applied
    call writefile(['edited meanwhile'], repo.'/tracked.txt')
    call project#git#Status()
    let lnum = s:Line('|work ')
    let messages = s:Messages({-> s:RangeCall('UnshelfFile', lnum, lnum)})
    call assert_match('Cannot unshelve \[tracked.txt\]: the changes conflict', messages)
    call assert_match('error: patch failed', messages)
    call assert_equal(['edited meanwhile'], readfile(repo.'/tracked.txt'))

    " Success is reported
    call system('git -C '.shellescape(repo).' restore tracked.txt')
    call project#git#Status()
    let lnum = s:Line('|work ')
    let messages = s:Messages({-> s:RangeCall('UnshelfFile', lnum, lnum)})
    call assert_match('Unshelved 1 file(s)', messages)
    call assert_equal(['shelved change'], readfile(repo.'/tracked.txt'))
  finally
    call s:CloseRepo()
  endtry
endfunction

" ---------------------------------------------------------------- layout

function! s:Column(bufname)
  let winid = bufwinid(bufnr('^'.a:bufname.'$'))
  return winid == -1 ? -1 : win_screenpos(winid)[1]
endfunction

" Lists on the left, details on the right, as in IDEs, whatever 'splitright'
function! Test_diff_opens_right_of_the_changelist()
  let repo = s:OpenRepo('layout changes')
  set nosplitright
  try
    call writefile(['changed'], repo.'/tracked.txt')
    call project#git#Status()
    call cursor(s:Line('|tracked\.txt|'), 1)
    call s:Call('ShowDiffOnChangelist')
    call assert_true(s:Column('diff') > s:Column('local_changes'),
          \ 'diff at column '.s:Column('diff').', changes at '.s:Column('local_changes'))
    call assert_equal(max([30, &columns * 2 / 5]), winwidth(bufwinnr('^local_changes$')))
  finally
    call s:CloseRepo()
  endtry
endfunction

function! Test_git_log_shows_changed_files_right_of_the_list()
  call s:OpenRepo('layout log')
  set nosplitright
  let s:log_layout = []
  " Recorded as the pane opens, not by a timer: Vim -es would read stdin
  " while the list waits for keys with none typed ahead
  augroup vim-project-test-log-layout
    autocmd!
    autocmd BufWinEnter changes
          \ let s:log_layout = [s:Column('changes'), s:Column('vim_project_list')]
  augroup END
  try
    call feedkeys("\<Esc>", 't')
    ProjectGitLog
    call assert_equal(2, len(s:log_layout))
    call assert_true(s:log_layout[0] > s:log_layout[1],
          \ 'changed files at column '.s:log_layout[0].', commits at '.s:log_layout[1])
  finally
    autocmd! vim-project-test-log-layout
    call s:CloseRepo()
  endtry
endfunction
