" Tests for autoload/project/git.vim status parsing and changelist helpers.
let s:file = 'autoload/project/git.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

function! s:Var(name)
  return Helper_ScriptVar(s:file, a:name)
endfunction

" Run a git command inside a:repo with a fixed identity.
function! s:Git(repo, args)
  let cmd = 'cd '.shellescape(a:repo).' && git -c user.name=test -c user.email=test@example.com'
        \.' -c commit.gpgsign=false -c core.autocrlf=false '.a:args
  let output = systemlist(cmd)
  return [v:shell_error, output]
endfunction

function! s:GitOk(repo, args)
  let [code, output] = s:Git(a:repo, a:args)
  call assert_equal(0, code, 'git '.a:args.' failed: '.join(output, "\n"))
endfunction

" Build a repository whose `git status --porcelain` contains:
"   AM both.txt       staged, then modified again
"   UU conflict.txt   merge conflict
"   ?? new.txt        untracked
"   A  staged.txt     staged new file
"    M tracked.txt    modified, unstaged
function! s:CreateStatusRepo()
  let repo = Helper_TmpDir('git repo with space')
  call s:GitOk(repo, 'init -q')
  call s:GitOk(repo, 'checkout -q -b main')
  call writefile(['tracked'], repo.'/tracked.txt')
  call writefile(['base'], repo.'/conflict.txt')
  call s:GitOk(repo, 'add -A && git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m init')

  call s:GitOk(repo, 'checkout -q -b other')
  call writefile(['other'], repo.'/conflict.txt')
  call s:GitOk(repo, 'commit -q -am other')

  call s:GitOk(repo, 'checkout -q main')
  call writefile(['main'], repo.'/conflict.txt')
  call s:GitOk(repo, 'commit -q -am main')

  " Merging must fail with a conflict
  let [code, output] = s:Git(repo, 'merge other')
  call assert_notequal(0, code, 'expected a merge conflict')

  call writefile(['changed'], repo.'/tracked.txt')
  call writefile(['new'], repo.'/new.txt')
  call writefile(['staged'], repo.'/staged.txt')
  call writefile(['both'], repo.'/both.txt')
  call s:GitOk(repo, 'add staged.txt both.txt')
  call writefile(['both', 'again'], repo.'/both.txt')
  return repo
endfunction

function! Test_ParseGitStatus_classifies_porcelain_output()
  if !executable('git')
    return
  endif
  let repo = s:CreateStatusRepo()
  if !empty(v:errors)
    return
  endif

  let saved = $vim_project
  let $vim_project = repo
  try
    call s:Call('ParseGitStatus')
  finally
    let $vim_project = saved
  endtry

  call assert_equal(['A both.txt', 'A staged.txt'], sort(s:Var('staged_files')))
  call assert_equal(['M tracked.txt'], s:Var('changed_files'))
  call assert_equal(['? new.txt'], s:Var('untracked_files'))
  call assert_equal(['U conflict.txt'], s:Var('unmerged_files'))
endfunction

function! Test_ParseGitStatus_clean_repo_resets_lists()
  if !executable('git')
    return
  endif
  let repo = Helper_TmpDir('git-clean')
  call s:GitOk(repo, 'init -q')
  call writefile(['x'], repo.'/a.txt')
  call s:GitOk(repo, 'add -A && git -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false commit -q -m init')

  let saved = $vim_project
  let $vim_project = repo
  try
    call s:Call('ParseGitStatus')
  finally
    let $vim_project = saved
  endtry

  call assert_equal([], s:Var('staged_files'))
  call assert_equal([], s:Var('changed_files'))
  call assert_equal([], s:Var('untracked_files'))
  call assert_equal([], s:Var('unmerged_files'))
endfunction

" ---------------------------------------------------------------- folders

function! Test_GetDefaultFolder_returns_independent_copies()
  let first = s:Call('GetDefaultFolder', 'Staged')
  call assert_equal({'name': 'Staged', 'files': [], 'expand': 0}, first)

  call add(first.files, 'touched.txt')
  let first.expand = 1

  let second = s:Call('GetDefaultFolder', 'Staged')
  call assert_equal([], second.files)
  call assert_equal(0, second.expand)

  " The template list itself must stay untouched
  for folder in s:Var('changelist_default')
    call assert_equal([], folder.files, folder.name)
  endfor
endfunction

function! Test_GetDefaultFolder_known_names()
  call assert_equal(1, s:Call('GetDefaultFolder', 'Default').expand)
  call assert_equal(0, s:Call('GetDefaultFolder', 'Unmerged').expand)
  call assert_equal(0, s:Call('GetDefaultFolder', 'Untracked').expand)
endfunction

function! Test_GetDefaultFolder_unknown_name_gets_empty_folder()
  call assert_equal({'name': 'Custom', 'files': [], 'expand': 0},
        \ s:Call('GetDefaultFolder', 'Custom'))
endfunction

" ---------------------------------------------------------------- sorting

function! Test_SortChangelistFunc_default_first_then_user_folders_by_name()
  let list = [
        \{'name': 'Staged', 'files': []},
        \{'name': 'beta', 'files': []},
        \{'name': 'Default', 'files': []},
        \{'name': 'shelf-a', 'files': [], 'shelf': 1},
        \{'name': 'alpha', 'files': []},
        \{'name': 'Untracked', 'files': []},
        \{'name': 'Unmerged', 'files': []},
        \]
  let sorted = sort(copy(list), Helper_Funcref(s:file, 'SortChangelistFunc'))
  let names = map(copy(sorted), {_, item -> item.name})

  call assert_equal(['Default', 'alpha', 'beta'], names[0:2])
  " Special and shelf folders all trail the user folders
  call assert_equal(['Staged', 'Unmerged', 'Untracked', 'shelf-a'], sort(names[3:]))
endfunction

function! Test_SortChangelistFunc_pairwise_rules()
  let Sort = Helper_Funcref(s:file, 'SortChangelistFunc')
  let default = {'name': 'Default'}
  let user_a = {'name': 'a'}
  let user_b = {'name': 'b'}
  let staged = {'name': 'Staged'}
  let shelf = {'name': 'x', 'shelf': 1}

  call assert_equal(-1, Sort(default, user_a))
  call assert_equal(1, Sort(user_a, default))
  call assert_equal(-1, Sort(user_a, user_b))
  call assert_equal(1, Sort(user_b, user_a))
  call assert_equal(-1, Sort(user_b, staged))
  call assert_equal(1, Sort(staged, user_a))
  call assert_equal(-1, Sort(user_b, shelf))
  call assert_equal(1, Sort(shelf, user_a))
endfunction
