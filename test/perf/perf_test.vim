" Performance budgets of the hot paths: code that runs on every key typed in
" a list, or when a list opens. Run with
"
"   VIM_PROJECT_TEST_CASES=perf bash test/run.sh
"
" Each budget is several times what the code takes on a laptop, so slower
" CI machines pass, while regressions like those that slipped through
" before (10x to 100x slower) fail. Data is generated at a realistic scale.
let s:sf = 'autoload/project/search_files.vim'
let s:git = 'autoload/project/git.vim'
runtime autoload/project/search_files.vim
runtime autoload/project/git.vim

" Best of 3 runs, in ms
function! s:Ms(Fn, args)
  let best = -1.0
  for i in range(3)
    let start = reltime()
    call call(a:Fn, a:args)
    let ms = reltimefloat(reltime(start)) * 1000
    let best = best < 0 || ms < best ? ms : best
  endfor
  return best
endfunction

" Checks a:ms against a:budget, and adds a line to $VIM_PROJECT_PERF_REPORT
function! s:Budget(ms, budget, what)
  let line = printf('%-42s %7.1f ms  (budget %d ms)', a:what, a:ms, a:budget)
  if !empty($VIM_PROJECT_PERF_REPORT)
    call writefile([line], $VIM_PROJECT_PERF_REPORT, 'a')
  endif
  call assert_true(a:ms < a:budget, line)
endfunction

function! s:SetMaxSize()
  let state = project#list#State()
  let state.max_height = 40
  let state.max_width = 200
endfunction

" A project of 40k files in 400 folders, made once
function! s:BigProject()
  if exists('s:big')
    return s:big
  endif
  let s:big = Helper_TmpDir('perf big')
  call system('cd '.shellescape(s:big).' && for i in $(seq 1 400); do mkdir -p pkg$i/src; '
        \.'(cd pkg$i/src && touch $(seq -f "file%g.js" 1 100)); done')
  return s:big
endfunction

function! s:WithProject(dir, Fn)
  let config = project#config#All()
  let saved = [$vim_project, config.search_include, config.search_exclude]
  let $vim_project = a:dir
  let config.search_include = ['.']
  let config.search_exclude = ['.git', 'node_modules']
  call project#search_files#Reset()
  call s:SetMaxSize()
  try
    call a:Fn()
  finally
    call project#search_files#Reset()
    let [$vim_project, config.search_include, config.search_exclude] = saved
  endtry
endfunction

" ---------------------------------------------------------------- search files

" Recent files are filtered on every key. Most of v:oldfiles is outside the
" project; asking the file system about each made typing lag (200 ms)
function! s:CheckRecentFiles(outside)
  let saved = copy(v:oldfiles)
  call filter(v:oldfiles, 0)
  call extend(v:oldfiles, map(range(1, 50), {_, i -> s:big.'/pkg'.i.'/src/file1.js'}))
  call extend(v:oldfiles, a:outside)
  try
    let ms = s:Ms(Helper_Funcref(s:sf, 'GetSearchFilesByOldFiles'), ['file'])
    call s:Budget(ms, 40, 'filtering 350 recent files')
  finally
    call filter(v:oldfiles, 0)
    call extend(v:oldfiles, saved)
  endtry
endfunction

function! Test_perf_recent_files_per_key()
  call s:BigProject()
  " 300 recent files outside the project behind a chain of 30 symlinks, so
  " asking the file system about them is costly, as on slow disks
  let outside = Helper_TmpDir('perf outside')
  let deep = 'a/b/c/d/e/f/g/h/i/j/k/l/m/n/o/p/q/r/s/t'
  call system('cd '.shellescape(outside).' && mkdir -p real/'.deep
        \.' && (cd real/'.deep.' && touch $(seq -f "x%g.txt" 1 300))'
        \.' && prev=real && for i in $(seq 1 30); do ln -s $prev l$i; prev=l$i; done')
  let paths = map(range(1, 300), {_, i -> outside.'/l30/'.deep.'/x'.i.'.txt'})
  call s:WithProject(s:big, function('s:CheckRecentFiles', [paths]))
endfunction

function! s:CheckSearchKey()
  call Helper_Call(s:sf, 'GetSearchFilesAll', [])
  let ms = s:Ms(Helper_Funcref(s:sf, 'GetSearchFilesResult'), ['fil5'])
  call s:Budget(ms, 150, 'a key in search files over 40k files')
endfunction

function! Test_perf_search_files_per_key()
  call s:WithProject(s:BigProject(), function('s:CheckSearchKey'))
endfunction

" A background refresh that finds the same files must not rebuild 40k items
function! s:CheckRefreshUnchanged()
  call Helper_Call(s:sf, 'GetSearchFilesAll', [])
  let lines = project#RunShellCmd(Helper_Call(s:sf, 'GetListFilesCmd', []))
  call assert_true(len(lines) > 40000)
  let ms = s:Ms({-> Helper_Call(s:sf, 'ApplyRefresh', [reverse(copy(lines))])}, [])
  call s:Budget(ms, 100, 'a refresh with no change over 40k files')
endfunction

function! Test_perf_refresh_without_changes()
  call s:WithProject(s:BigProject(), function('s:CheckRefreshUnchanged'))
endfunction

" ---------------------------------------------------------------- git log

function! Test_perf_git_log()
  call s:SetMaxSize()
  let logs = map(range(1, 20000), {_, i ->
        \ printf('Commit %d: update module%d feature%d ||| Dev%d ||| d@x ||| %d days ago ||| h%05d',
        \ i, i % 50, i % 7, i % 13, i % 400, i)})
  let list = Helper_Call(s:git, 'GetTabulatedList', [logs])
  call s:Budget(s:Ms(Helper_Funcref(s:git, 'GetTabulatedList'), [logs]), 400, 'parsing 20k commits')
  call s:Budget(s:Ms(Helper_Funcref(s:git, 'FilterLogs'), [list, 'feature3']), 150, 'filtering 20k commits')
  " Rows are formatted once, then cached: time the first display only
  let state = project#list#State()
  let state.list = Helper_Call(s:git, 'FilterLogs', [list, 'f'])
  let start = reltime()
  call Helper_Call(s:git, 'GetLogsDisplay', [state.list, 'f'])
  call s:Budget(reltimefloat(reltime(start)) * 1000, 400, 'showing 20k commits')
endfunction

" ---------------------------------------------------------------- startup

" Loading the project list was quadratic in the number of projects: 2000
" makes that 4 times slower than for 1000, while it should be twice
function! Test_perf_load_2000_projects()
  let base = Helper_TmpDir('perf projects')
  call system('cd '.shellescape(base).' && mkdir $(seq -f "p%g" 1 2000)')
  let add_file = expand(project#config#Get('config_home')).'/project.add.vim'
  let saved = filereadable(add_file) ? readfile(add_file) : []
  call writefile(map(range(1, 2000), {_, i -> 'Project '.base.'/p'.i}), add_file)
  let projects = project#GetProjects()
  let before = len(projects)
  try
    let start = reltime()
    call Helper_Call('autoload/project.vim', 'SourcePluginConfigFiles', [])
    let ms = reltimefloat(reltime(start)) * 1000
    call assert_equal(before + 2000, len(projects))
    call s:Budget(ms, 2500, 'loading 2000 projects')
  finally
    call filter(projects, {_, p -> stridx(p.fullpath, base) != 0})
    call writefile(saved, add_file)
  endtry
endfunction
