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

" ---------------------------------------------------------------- git log

function! Test_GetChangedFiles_runs_git_once_per_commit()
  let dir = Helper_TmpDir('git-log-cache')
  let git = 'git -C '.shellescape(dir).' -c user.name=t -c user.email=t@t '
  call system(git.'init -q')
  call writefile(['a'], dir.'/a.txt')
  call system(git.'add a.txt && '.git.'commit -q -m first')
  let hash = trim(system(git.'rev-parse --short HEAD'))

  let saved_project = $vim_project
  let $vim_project = dir
  try
    call Helper_Call(s:file, 'InitGitLog', [''])
  catch
    " Init also renders the list, which needs the list window; the cache
    " reset at its start is what matters here
  endtry
  try
    let revision = {'hash': hash}
    let first = Helper_Call(s:file, 'GetChangedFiles', [revision])
    call assert_equal(1, len(first))
    call assert_match('a\.txt', first[0])
    call assert_true(has_key(s:Var('changed_files_cache'), hash))

    " Second call is served from the cache: same list, no new git run
    let second = Helper_Call(s:file, 'GetChangedFiles', [revision])
    call assert_true(first is second)

    call Helper_Call(s:file, 'CloseGitLog', [])
    call assert_equal({}, s:Var('changed_files_cache'))
  finally
    let $vim_project = saved_project
  endtry
endfunction

function! s:Logs(count)
  return map(range(1, a:count), {_, i ->
        \ printf('message %d fix%d ||| Dev%d ||| d@x ||| %d days ago ||| h%05d', i, i % 3, i % 2, i, i)})
endfunction

function! Test_GetTabulatedList_parses_most_recent_last()
  let list = Helper_Call(s:file, 'GetTabulatedList', [s:Logs(3)])
  " git log prints the most recent first; the list shows it at the bottom
  call assert_equal(['h00003', 'h00002', 'h00001'], map(copy(list), 'v:val.hash'))
  call assert_equal('1d ago', list[-1].date)
  call assert_false(has_key(list[0], '_row'))
endfunction

function! Test_FilterLogs_matches_words_within_one_field()
  let list = Helper_Call(s:file, 'GetTabulatedList', [s:Logs(6)])
  let Filter = {input -> map(Helper_Call(s:file, 'FilterLogs', [list, input]), 'v:val.hash')}
  call assert_equal(['h00003', 'h00006'], sort(Filter('fix0')))
  " Words in order: 'message 5 fix2' has no 'fix' after the '2'
  call assert_equal(['h00002'], Filter('message 2 fix'))
  " Words may not be split across message and author
  call assert_equal([], Filter('fix1 Dev1'))
  call assert_equal(['h00004'], Filter('h00004'))
  " Input starting with a digit also matches the date
  call assert_equal(['h00005'], Filter('5d'))
  " Literal: '.' is not a wildcard
  call assert_equal([], Filter('message.2'))
endfunction

function! Test_GetLogsDisplay_shows_most_recent_and_formats_once()
  let state = project#list#State()
  let saved = get(state, 'list', [])
  let max = Helper_ScriptVar(s:file, 'log_show_max')
  let list = Helper_Call(s:file, 'GetTabulatedList', [s:Logs(max + 5)])
  try
    let state.list = list
    let display = Helper_Call(s:file, 'GetLogsDisplay', [list, ''])
    call assert_equal(max, len(display))
    call assert_equal(max, len(state.list))
    " The list was cut to the most recent commits, newest at the bottom
    call assert_equal('h00001', state.list[-1].hash)
    call assert_match('\.\.\.more$', display[0])
    " Older commits are not formatted
    call assert_false(has_key(list[0], '_row'))
    call assert_true(has_key(list[-1], '_row'))
  finally
    let state.list = saved
  endtry
endfunction

" ---------------------------------------------------------------- commit

function! s:CommitRepo(name)
  let dir = Helper_TmpDir(a:name)
  let git = 'git -C '.shellescape(dir).' -c user.name=t -c user.email=t@t '
  call system(git.'init -q')
  for name in ['other.txt', 'mine.txt', 'gone.txt', 'partial.txt']
    call writefile([name], dir.'/'.name)
  endfor
  call system(git.'add . && '.git.'commit -q -m init')
  return [dir, git]
endfunction

function! s:CommittedFiles(git)
  return sort(split(system(a:git.'show --name-only --pretty=format: HEAD'), "\n"))
endfunction

function! s:WithProject(dir, Fn)
  let saved = $vim_project
  let $vim_project = a:dir
  try
    call a:Fn()
  finally
    let $vim_project = saved
  endtry
endfunction

function! s:CheckCommitOnlyGivenFiles(dir, git)
  " other.txt is staged but belongs to another changelist
  call writefile(['changed'], a:dir.'/other.txt')
  call system(a:git.'add other.txt')
  call writefile(['changed'], a:dir.'/mine.txt')
  call delete(a:dir.'/gone.txt')
  call writefile(['new'], a:dir.'/new.txt')

  let [cmd, _] = s:Call('RunCommit', ['mine.txt', 'gone.txt', 'new.txt'], ['msg with $HOME `x`'], 0, 0)
  call assert_equal(['gone.txt', 'mine.txt', 'new.txt'], s:CommittedFiles(a:git))
  call assert_equal('msg with $HOME `x`', trim(system(a:git.'log -1 --pretty=%s')))
  " The other change is still staged, not committed
  call assert_equal(['other.txt'], split(system(a:git.'diff --cached --name-only'), "\n"))
endfunction

function! Test_RunCommit_commits_only_the_changelist_files()
  let [dir, git] = s:CommitRepo('commit-only')
  call s:WithProject(dir, function('s:CheckCommitOnlyGivenFiles', [dir, git]))
endfunction

function! s:CheckCommitStagedKeepsPartialStaging(dir, git)
  " Stage only the first line of partial.txt, keep the second unstaged
  call writefile(['partial.txt', 'staged line'], a:dir.'/partial.txt')
  call system(a:git.'add partial.txt')
  call writefile(['partial.txt', 'staged line', 'unstaged line'], a:dir.'/partial.txt')

  call s:Call('RunCommit', ['partial.txt'], ['staged'], 0, 1)
  call assert_equal(['partial.txt', 'staged line'],
        \ split(system(a:git.'show HEAD:partial.txt'), "\n"))
  call assert_equal(['partial.txt'], split(system(a:git.'diff --name-only'), "\n"))
endfunction

function! Test_RunCommit_staged_changelist_keeps_partial_staging()
  let [dir, git] = s:CommitRepo('commit-staged')
  call s:WithProject(dir, function('s:CheckCommitStagedKeepsPartialStaging', [dir, git]))
endfunction

function! s:CheckAmend(dir, git)
  call writefile(['changed'], a:dir.'/mine.txt')
  call s:Call('RunCommit', ['mine.txt'], [], 1, 0)
  call assert_equal('init', trim(system(a:git.'log -1 --pretty=%s')))
  call assert_equal('1', trim(system(a:git.'rev-list --count HEAD')))
  call assert_equal(['changed'], split(system(a:git.'show HEAD:mine.txt'), "\n"))
endfunction

function! Test_RunCommit_amend_keeps_message()
  let [dir, git] = s:CommitRepo('commit-amend')
  call s:WithProject(dir, function('s:CheckAmend', [dir, git]))
endfunction

" ---------------------------------------------------------------- shelf

function! Test_DeleteShelfFolder_asks_first()
  let dir = Helper_TmpDir('shelf').'/my shelf'
  call mkdir(dir, 'p')
  call writefile(['patch'], dir.'/a.txt.diff')

  " Anything but 'y' keeps the patches
  call feedkeys('n', 't')
  call assert_equal(0, s:Call('DeleteShelfFolder', dir, 'my shelf', 1))
  call assert_true(filereadable(dir.'/a.txt.diff'))

  call feedkeys('y', 't')
  call assert_equal(1, s:Call('DeleteShelfFolder', dir, 'my shelf', 1))
  call assert_false(isdirectory(dir))
endfunction
