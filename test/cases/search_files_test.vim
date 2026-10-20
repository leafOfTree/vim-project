" Tests for autoload/project/search_files.vim filtering.
let s:file = 'autoload/project/search_files.vim'
runtime autoload/project/search_files.vim

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

function! s:Item(file, ...)
  return {'file': a:file, 'path': a:0 ? a:1 : ''}
endfunction

" Matched file names, deduplicated: the filter may add a file once per pass
function! s:Files(list)
  return uniq(sort(map(copy(a:list), {_, val -> val.file})))
endfunction

" state.max_height is normally set when the list window opens
function! s:WithMaxHeight(Func)
  let state = project#list#State()
  let had_key = has_key(state, 'max_height')
  let saved = get(state, 'max_height', 0)
  let state.max_height = 10
  try
    call a:Func()
  finally
    if had_key
      let state.max_height = saved
    else
      call remove(state, 'max_height')
    endif
  endtry
endfunction

let s:items = [
      \s:Item('a.b'),
      \s:Item('axb'),
      \s:Item('c[1]'),
      \s:Item('star*'),
      \s:Item('rx'),
      \s:Item('x~y'),
      \]

function! s:CheckFilterForAll()
  let list = s:items
  call assert_equal(['x~y'], s:Files(s:Call('GetSearchFilesByFilter', list, '~')))
  call assert_equal(['a.b'], s:Files(s:Call('GetSearchFilesByFilter', list, 'a.b')))
  call assert_equal(['c[1]'], s:Files(s:Call('GetSearchFilesByFilter', list, '[1')))
  call assert_equal(['star*'], s:Files(s:Call('GetSearchFilesByFilter', list, 'r*')))
  " Prefix match for short input is literal too
  call assert_equal(['a.b'], s:Files(s:Call('GetSearchFilesByFilterForAll', list, 'a.')))
  " Fuzzy match still allows anything between typed chars
  call assert_equal(['star*'], s:Files(s:Call('GetSearchFilesByFilterForAll', list, 's*')))
endfunction

" Regression: '~' raised E33 and '.', '*', '[' were used as regexp
function! Test_SearchFilesFilter_matches_typed_chars_literally()
  call s:WithMaxHeight(function('s:CheckFilterForAll'))
endfunction

function! s:CheckFilterForDirectory()
  let root = Helper_TmpDir('search files dirs')
  let names = ['a.b', 'axb', 'c[1', 'r*x', 'rx', 'q~']
  for name in names
    call mkdir(root.'/'.name, 'p')
  endfor
  " A file is never a directory match
  call writefile([], root.'/a.b.txt')
  let list = map(names + ['a.b.txt'], {_, name -> s:Item(name)})

  let saved = $vim_project
  let $vim_project = root
  try
    call assert_equal(['q~'], s:Files(s:Call('GetSearchFilesByFilter', list, '~/')))
    call assert_equal(['a.b'], s:Files(s:Call('GetSearchFilesByFilter', list, 'a.b/')))
    call assert_equal(['c[1'], s:Files(s:Call('GetSearchFilesByFilter', list, '[1/')))
    call assert_equal(['r*x'], s:Files(s:Call('GetSearchFilesByFilter', list, 'r*/')))
  finally
    let $vim_project = saved
  endtry
endfunction

function! Test_SearchFilesFilter_directory_mode_matches_literally()
  call s:WithMaxHeight(function('s:CheckFilterForDirectory'))
endfunction

function! Test_FilterOldFilesByInput_matches_typed_chars_literally()
  for [input, expected] in [['~', ['x~y']], ['a.b', ['a.b']], ['[1', ['c[1]']], ['r*', ['star*']]]
    let oldfiles = deepcopy(s:items)
    call s:Call('FilterOldFilesByInput', oldfiles, input)
    call assert_equal(expected, s:Files(oldfiles), 'input: '.input)
  endfor
endfunction

" ---------------------------------------------------------------- refresh

" Names in the cached file list, from s:initial_list
function! s:CachedFiles()
  return sort(map(s:Call('GetSearchFilesByFilter', s:CachedList(), ''),
        \ {_, val -> val.file}))
endfunction

function! s:CachedList()
  return Helper_ScriptVar(s:file, 'initial_list')
endfunction

function! s:WaitRefresh()
  let tries = 0
  while s:Call('IsRefreshing') && tries < 300
    sleep 10m
    let tries += 1
  endwhile
  " Let the exit callback run
  sleep 50m
endfunction

function! s:WithProject(dir, Func)
  let config = project#config#All()
  let saved = [$vim_project, config.search_include, config.search_exclude]
  let $vim_project = a:dir
  let config.search_include = ['.']
  let config.search_exclude = ['.git']
  call project#search_files#Reset()
  try
    call a:Func()
  finally
    call project#search_files#Reset()
    let [$vim_project, config.search_include, config.search_exclude] = saved
  endtry
endfunction

function! s:RefreshPicksUpChanges(dir)
  call s:Call('GetSearchFilesAll')
  call assert_equal(['a.txt', 'gone.txt'],
        \ sort(map(copy(s:CachedList()), {_, val -> val.file})))

  " Changed outside Vim: one file added, one removed
  call writefile(['new'], a:dir.'/added.txt')
  call delete(a:dir.'/gone.txt')

  call s:Call('StartRefresh')
  call s:WaitRefresh()
  call assert_equal(['a.txt', 'added.txt'],
        \ sort(map(copy(s:CachedList()), {_, val -> val.file})))
endfunction

function! Test_StartRefresh_picks_up_files_changed_outside_vim()
  if !s:Call('CanRefresh') || empty(s:Call('GetListFilesCmd'))
    return
  endif
  let dir = Helper_TmpDir('search-refresh')
  call writefile(['a'], dir.'/a.txt')
  call writefile(['g'], dir.'/gone.txt')
  call s:WithProject(dir, function('s:RefreshPicksUpChanges', [dir]))
endfunction

function! s:ResetDiscardsRefresh(dir)
  call s:Call('GetSearchFilesAll')
  call writefile(['new'], a:dir.'/late.txt')
  call s:Call('StartRefresh')
  " Reset while the job runs: its result must not come back
  call project#search_files#Reset()
  call s:WaitRefresh()
  sleep 200m
  call assert_false(has_key(Helper_ScriptVars(s:file), 'initial_list'))
endfunction

function! Test_Reset_discards_a_running_refresh()
  if !s:Call('CanRefresh') || empty(s:Call('GetListFilesCmd'))
    return
  endif
  let dir = Helper_TmpDir('search-refresh-reset')
  call writefile(['a'], dir.'/a.txt')
  call s:WithProject(dir, function('s:ResetDiscardsRefresh', [dir]))
endfunction

function! s:RefreshKeepsUnchangedList(dir)
  call s:Call('GetSearchFilesAll')
  let before = s:CachedList()
  call s:Call('StartRefresh')
  call s:WaitRefresh()
  " Same files: the cache is kept as is, so the list is not redrawn
  call assert_true(before is s:CachedList() || before == s:CachedList())
  call assert_equal(['a.txt'], map(copy(s:CachedList()), {_, val -> val.file}))
endfunction

function! Test_StartRefresh_keeps_unchanged_list()
  if !s:Call('CanRefresh') || empty(s:Call('GetListFilesCmd'))
    return
  endif
  let dir = Helper_TmpDir('search-refresh-same')
  call writefile(['a'], dir.'/a.txt')
  call s:WithProject(dir, function('s:RefreshKeepsUnchangedList', [dir]))
endfunction

" ---------------------------------------------------------------- fuzzy ranking

function! Test_MapSearchFiles_handles_fd_directories()
  let list = ['src/', 'src/app.js', 'a/b/c/', 'README.md']
  call s:Call('MapSearchFiles', list)
  call assert_equal({'file': 'src', 'path': '', 'dir': 1}, list[0])
  call assert_equal({'file': 'app.js', 'path': 'src'}, list[1])
  call assert_equal({'file': 'c', 'path': 'a/b', 'dir': 1}, list[2])
  call assert_equal({'file': 'README.md', 'path': ''}, list[3])
endfunction

function! s:FuzzyNames(list, input)
  return map(s:Call('GetSearchFilesByMatchFuzzy', a:list, a:input),
        \ {_, val -> empty(val.path) ? val.file : val.path.'/'.val.file})
endfunction

function! Test_GetSearchFilesByMatchFuzzy()
  if !exists('*matchfuzzy')
    return
  endif
  let list = ['router/', 'router/index.js', 'pkg3/router.js', 'pkg1/router.js',
        \ 'lib/util.js', 'componentController.ts', 'notes.md']
  call s:Call('MapSearchFiles', list)

  " Camel case and scattered characters
  call assert_equal('componentController.ts', s:FuzzyNames(list, 'cmpCtl')[0])
  " Files rank before a directory with the same name
  let router = s:FuzzyNames(list, 'router')
  call assert_equal('router', router[-1])
  call assert_true(index(router, 'pkg3/router.js') < index(router, 'router'))
  " Input with '/' matches the path in the project
  call assert_equal('pkg3/router.js', s:FuzzyNames(list, 'pkg3/rout')[0])
  " 'name/' lists directories only
  call assert_equal(['router'], s:FuzzyNames(list, 'rout/'))
  " No match
  call assert_equal([], s:FuzzyNames(list, 'zzzz'))
endfunction

" ---------------------------------------------------------------- real programs

" List files with each program for real; all must agree
function! s:ListWith(program)
  let name = {'fd': 'GetFilesByFd', 'find': 'GetFilesByFind', 'glob': 'GetFilesByGlob'}[a:program]
  let lines = s:Call(name)
  " './a' (find, glob) and 'a/' (fd directories) are the same path
  call map(lines, {_, line -> substitute(substitute(line, '^\.[/\\]', '', ''), '[/\\]$', '', '')})
  return uniq(sort(lines))
endfunction

function! s:CheckListPrograms(dir)
  let expected = ['.env', 'a.txt', 'sub', 'sub/.hidden_dir', 'sub/.hidden_dir/c.txt',
        \ 'sub/b.txt', 'with space', 'with space/d.txt']
  for program in ['fd', 'find', 'glob']
    if program !=# 'glob' && !executable(program)
      continue
    endif
    call assert_equal(expected, s:ListWith(program), program)
  endfor
endfunction

function! Test_list_programs_agree_for_real()
  let dir = Helper_TmpDir('list programs')
  for sub in ['sub/.hidden_dir', 'with space', 'node_modules/pkg']
    call mkdir(dir.'/'.sub, 'p')
  endfor
  for file in ['a.txt', '.env', 'sub/b.txt', 'sub/.hidden_dir/c.txt',
        \ 'with space/d.txt', 'node_modules/pkg/x.js']
    call writefile(['x'], dir.'/'.file)
  endfor

  let config = project#config#All()
  let saved = [$vim_project, config.search_include, config.search_exclude]
  let $vim_project = dir
  let config.search_include = ['.']
  let config.search_exclude = ['node_modules']
  try
    call s:CheckListPrograms(dir)
  finally
    let [$vim_project, config.search_include, config.search_exclude] = saved
  endtry
endfunction

" ---------------------------------------------------------------- recent files

" A project opened through a symlink: v:oldfiles may hold the real path of
" its files (Neovim resolves them), which must still map to 'src', not to a
" mangled '/private...' path, and appear once
function! s:CheckRecentFiles(link, real)
  let saved = copy(v:oldfiles)
  call filter(v:oldfiles, 0)
  call extend(v:oldfiles, [a:real.'/src/a.js', a:link.'/src/a.js', a:real.'/node_modules/x.js',
        \ a:real.'-other/src/b.js', a:link.'/gone.js'])
  try
    let items = s:Call('GetSearchFilesByOldFiles', '')
    call assert_equal([{'file': 'a.js', 'path': 'src'}], items)
  finally
    call filter(v:oldfiles, 0)
    call extend(v:oldfiles, saved)
  endtry
endfunction

function! Test_recent_files_of_a_project_opened_through_a_symlink()
  " Like /tmp -> /private/tmp on macOS: the real path is a prefix followed
  " by the whole path of the link
  let base = resolve(Helper_TmpDir('recent'))
  let link_dir = base.'/link'
  let real_dir = base.'/private'.link_dir
  let real = real_dir.'/proj'
  call mkdir(real.'/src', 'p')
  call mkdir(real.'/node_modules', 'p')
  call mkdir(real.'-other/src', 'p')
  call writefile(['a'], real.'/src/a.js')
  call writefile(['x'], real.'/node_modules/x.js')
  call writefile(['b'], real.'-other/src/b.js')
  call system('ln -s '.shellescape(real_dir).' '.shellescape(link_dir))
  let link = link_dir.'/proj'
  if !isdirectory(link)
    return
  endif

  let config = project#config#All()
  let saved = [$vim_project, config.search_exclude]
  let $vim_project = link
  let config.search_exclude = ['node_modules']
  try
    call s:CheckRecentFiles(link, real)
  finally
    let [$vim_project, config.search_exclude] = saved
  endtry
endfunction
