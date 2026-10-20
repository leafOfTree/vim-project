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

function! Test_ShelfFile_and_UnshelfFile()
  let repo = s:OpenRepo('shelf')
  try
    call writefile(['shelved change'], repo.'/tracked.txt')
    call writefile(['deep change'], repo.'/sub/deep.txt')
    call project#git#Status()

    " Shelve each file into the shelf 'work'
    for pattern in ['|tracked\.txt|', '|deep\.txt|']
      let lnum = s:Line(pattern)
      call feedkeys("work\<CR>", 't')
      call s:RangeCall('ShelfFile', lnum, lnum)
    endfor
    let shelf = $vim_project_config.'/shelf/work'
    call assert_match('+shelved change', join(readfile(shelf.'/tracked.txt.diff'), "\n"))
    " A file in a sub directory is saved as 'dir+name'
    call assert_match('+deep change', join(readfile(shelf.'/sub+deep.txt.diff'), "\n"))
    call assert_equal(['sub+deep.txt.diff', 'tracked.txt.diff'], s:FolderFiles('work'))

    " Shelving keeps the change in the working tree; roll it back first
    call assert_equal(['shelved change'], readfile(repo.'/tracked.txt'))
    call system('git -C '.shellescape(repo).' restore .')
    call project#git#Status()

    " Unshelve the whole shelf from its line
    let lnum = s:Line('|work ')
    call s:RangeCall('UnshelfFile', lnum, lnum)
    call assert_equal(['shelved change'], readfile(repo.'/tracked.txt'))
    call assert_equal(['deep change'], readfile(repo.'/sub/deep.txt'))

    " Unshelve a single file of the shelf
    call system('git -C '.shellescape(repo).' restore .')
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
