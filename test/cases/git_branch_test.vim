" Tests of the branch list: merging the selected branch (<C-o>)

function! s:Git(repo, args)
  return system('git -C '.shellescape(a:repo).' '.a:args)
endfunction

" A project whose repository has a branch 'feature' with one more commit,
" changing a:feature_file. The current branch stays the first one
function! s:OpenRepo(name, feature_file)
  let base = Helper_TmpDir(a:name)
  let repo = base.'/proj'
  call mkdir(repo, 'p')
  call writefile(['one'], repo.'/tracked.txt')
  call s:Git(repo, 'init -q')
  call s:Git(repo, 'config user.name t')
  call s:Git(repo, 'config user.email t@t')
  call s:Git(repo, 'add .')
  call s:Git(repo, 'commit -q -m init')
  call s:Git(repo, 'checkout -q -b feature')
  call writefile(['feature'], repo.'/'.a:feature_file)
  call s:Git(repo, 'add .')
  call s:Git(repo, 'commit -q -m feature')
  call s:Git(repo, 'checkout -q -')

  let project = {'name': 'proj', 'path': base, 'fullpath': repo, 'note': '', 'option': {}}
  call Helper_Call('autoload/project.vim', 'InitProjectConfig', [project])
  call project#OpenProject(project)
  return repo
endfunction

function! s:CloseRepo(repo)
  call s:Git(a:repo, 'merge --abort')
  call project#QuitProject()
  silent! %bwipeout!
endfunction

function! Test_merge_branch_asks_first()
  let repo = s:OpenRepo('merge branch', 'feature.txt')
  try
    " 'n' keeps the list open without merging, <Esc> closes it
    call feedkeys("feature\<C-o>n\<Esc>", 't')
    ProjectGitBranch
    call assert_false(filereadable(repo.'/feature.txt'))

    " 'y' merges and closes the list
    call feedkeys("feature\<C-o>y", 't')
    ProjectGitBranch
    call assert_equal(['feature'], readfile(repo.'/feature.txt'))
    call assert_equal(-1, bufwinnr('vim_project_list'))
  finally
    call s:CloseRepo(repo)
  endtry
endfunction

function! Test_merge_branch_with_conflict_leaves_it_to_resolve()
  let repo = s:OpenRepo('merge conflict', 'tracked.txt')
  try
    call writefile(['mine'], repo.'/tracked.txt')
    call s:Git(repo, 'commit -q -am mine')

    call feedkeys("feature\<C-o>y", 't')
    silent! ProjectGitBranch
    " The list closes, the conflict is there to resolve in local changes
    call assert_equal(-1, bufwinnr('vim_project_list'))
    call assert_match('UU tracked.txt', s:Git(repo, 'status --porcelain'))
  finally
    call s:CloseRepo(repo)
  endtry
endfunction
