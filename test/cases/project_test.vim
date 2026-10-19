" Tests for autoload/project.vim helpers.
let s:file = 'autoload/project.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

" The list UI and config merging live in their own scripts
let s:list_file = 'autoload/project/list.vim'
let s:config_file = 'autoload/project/config.vim'

function! s:ListCall(name, ...)
  " Make sure list.vim is autoloaded before looking up its <SNR>
  call project#list#State()
  return Helper_Call(s:list_file, a:name, a:000)
endfunction

function! s:ConfigCall(name, ...)
  return Helper_Call(s:config_file, a:name, a:000)
endfunction

" state.max_width is normally set when the list window opens; set it directly
" for Tabulate tests and return the previous value for restoring.
function! s:SetMaxWidth(width)
  let state = project#list#State()
  let saved = get(state, 'max_width', a:width)
  let state.max_width = a:width
  return saved
endfunction

" ---------------------------------------------------------------- paths

function! Test_IsRelativePath()
  call assert_equal(1, s:Call('IsRelativePath', 'foo'))
  call assert_equal(1, s:Call('IsRelativePath', 'foo/bar'))
  call assert_equal(1, s:Call('IsRelativePath', './foo'))
  call assert_equal(0, s:Call('IsRelativePath', '/abs/path'))
  call assert_equal(0, s:Call('IsRelativePath', '~/home/path'))
  call assert_equal(0, s:Call('IsRelativePath', 'C:\windows\path'))
  call assert_equal(0, s:Call('IsRelativePath', 'D:/unix/style'))
endfunction

function! Test_GetFullPath_absolute_path_strips_trailing_slash()
  call assert_equal('/abs/path', s:Call('GetFullPath', '/abs/path/'))
  call assert_equal('/abs/path', s:Call('GetFullPath', '/abs/path'))
endfunction

function! Test_GetFullPath_expands_home()
  let home = expand('~')
  call assert_equal(home.'/vim_project_test_nowhere',
        \ s:Call('GetFullPath', '~/vim_project_test_nowhere/'))
endfunction

function! Test_GetFullPath_relative_path_resolved_from_project_base()
  " g:vim_project_config.project_base points at <tmp>/base (see runner.vim)
  let base = g:vim_project_test_tmp.'/base'
  call mkdir(base.'/existing-project', 'p')
  call assert_equal(base.'/existing-project',
        \ s:Call('GetFullPath', 'existing-project/'))
endfunction

function! Test_GetFullPath_relative_path_falls_back_to_cwd()
  let dir = Helper_TmpDir('cwd')
  let saved = getcwd()
  try
    execute 'cd '.fnameescape(dir)
    " getcwd() may resolve symlinks (e.g. /tmp -> /private/tmp on macOS)
    call assert_equal(resolve(dir).'/not-created-yet',
          \ s:Call('GetFullPath', 'not-created-yet'))
  finally
    execute 'cd '.fnameescape(saved)
  endtry
endfunction

function! Test_ReplaceHomeWithTide()
  let home = expand('~')
  call assert_equal('~/repo/x', project#ReplaceHomeWithTide(home.'/repo/x'))
  call assert_equal('~', project#ReplaceHomeWithTide(home))
  call assert_equal('/other/path', project#ReplaceHomeWithTide('/other/path'))
  " Only a leading home directory is replaced
  call assert_equal('/prefix'.home, project#ReplaceHomeWithTide('/prefix'.home))
endfunction

" ---------------------------------------------------------------- input

function! Test_ClearCharOfInput_ascii()
  call assert_equal('ab', s:ListCall('ClearCharOfInput', 'abc'))
  call assert_equal('', s:ListCall('ClearCharOfInput', 'a'))
  call assert_equal('', s:ListCall('ClearCharOfInput', ''))
endfunction

function! Test_ClearCharOfInput_multibyte()
  " Removes one character, not one byte
  call assert_equal('中', s:ListCall('ClearCharOfInput', '中文'))
  call assert_equal('中文', s:ListCall('ClearCharOfInput', '中文字'))
  call assert_equal('abc中', s:ListCall('ClearCharOfInput', 'abc中文'))
  call assert_equal('', s:ListCall('ClearCharOfInput', '中'))
endfunction

function! Test_ClearWordOfInput()
  call assert_equal('foo ', s:ListCall('ClearWordOfInput', 'foo bar'))
  call assert_equal('foo ', s:ListCall('ClearWordOfInput', 'foo bar  '))
  call assert_equal('', s:ListCall('ClearWordOfInput', 'foo'))
  call assert_equal('', s:ListCall('ClearWordOfInput', 'foo   '))
  " A trailing run of non-word characters is removed as one unit
  call assert_equal('foo', s:ListCall('ClearWordOfInput', 'foo ..'))
  call assert_equal('foo.', s:ListCall('ClearWordOfInput', 'foo.bar'))
  call assert_equal('', s:ListCall('ClearWordOfInput', ''))
endfunction

" ---------------------------------------------------------------- display

function! Test_Truncate_by_display_width()
  " ASCII: keeps max_width - placeholder + 1 columns, then the placeholder
  call assert_equal('abcde..', s:ListCall('Truncate', 'abcdefgh', 6, '..'))
  " Wide characters are never split in half
  call assert_equal('中文..', s:ListCall('Truncate', '中文字符串', 6, '..'))
  call assert_equal('中文字..', s:ListCall('Truncate', '中文字符串', 7, '..'))
  call assert_equal('a中..', s:ListCall('Truncate', 'a中文字符', 5, '..'))
  let result = s:ListCall('Truncate', '中文字符串', 6, '.. ')
  call assert_true(strdisplaywidth(result) <= 7, 'width of '.result)
  call assert_match('\.\. $', result)
endfunction

function! Test_Tabulate_aligns_columns_by_display_width()
  let saved = s:SetMaxWidth(200)
  try
    let list = [
          \{'name': '中文名', 'path': '/a'},
          \{'name': 'ab', 'path': '/longer/path'},
          \{'name': 'x', 'path': '/b'},
          \]
    let columns = project#list#Tabulate(list, ['name', 'path'])

    " The items themselves are left untouched
    call assert_false(has_key(list[0], '__name'))
    " Every column gets the same display width
    for key in ['name', 'path']
      let widths = map(copy(columns), {_, column -> strdisplaywidth(column[key])})
      call assert_equal(1, len(uniq(sort(copy(widths)))),
            \ 'column '.key.' widths: '.string(widths))
    endfor
    " 中文名 is 6 columns wide, the widest name, so it gets one trailing space
    call assert_equal('中文名 ', columns[0].name)
    call assert_equal('ab     ', columns[1].name)
    call assert_equal('/longer/path ', columns[1].path)
  finally
    call s:SetMaxWidth(saved)
  endtry
endfunction

function! Test_Tabulate_respects_min_col_width()
  let saved = s:SetMaxWidth(200)
  try
    let list = [{'name': 'ab'}, {'name': 'c'}]
    let columns = project#list#Tabulate(list, ['name'], 10)
    call assert_equal(11, strdisplaywidth(columns[0].name))
    call assert_equal(11, strdisplaywidth(columns[1].name))
  finally
    call s:SetMaxWidth(saved)
  endtry
endfunction

function! Test_Tabulate_truncates_wide_values_when_too_wide()
  " Total width exceeds the list window, so values are cut to max_col_width
  let saved = s:SetMaxWidth(10)
  try
    let list = [{'name': repeat('字', 20)}, {'name': 'short'}]
    let columns = project#list#Tabulate(list, ['name'], 0, 8)
    call assert_equal('字字字..', matchstr(columns[0].name, '^字*\.\.'))
    call assert_true(strdisplaywidth(columns[0].name) <= 9,
          \ 'width of '.columns[0].name)
    call assert_equal(strdisplaywidth(columns[0].name),
          \ strdisplaywidth(columns[1].name))
  finally
    call s:SetMaxWidth(saved)
  endtry
endfunction

function! Test_Tabulate_replaces_home_with_tilde()
  let saved = s:SetMaxWidth(200)
  try
    let list = [{'path': expand('~').'/repo'}]
    let columns = project#list#Tabulate(list, ['path'])
    call assert_equal('~/repo ', columns[0].path)
  finally
    call s:SetMaxWidth(saved)
  endtry
endfunction

" ---------------------------------------------------------------- config

function! Test_MergeUserConfigIntoDefault_overrides_only_known_keys()
  let default = {
        \'debug': 0,
        \'exclude': ['.git'],
        \'list_mappings': {'open': "\<cr>", 'close_list': "\<esc>"},
        \}
  let user = {'debug': 1, 'exclude': ['dist'], 'unknown_key': 'ignored'}

  let result = s:ConfigCall('MergeUserConfigIntoDefault', user, default)

  call assert_equal(1, result.debug)
  call assert_equal(['dist'], result.exclude)
  call assert_false(has_key(result, 'unknown_key'))
  call assert_equal({'open': "\<cr>", 'close_list': "\<esc>"}, result.list_mappings)
endfunction

function! Test_MergeUserConfigIntoDefault_merges_nested_mappings()
  let default = {
        \'list_mappings': {'open': "\<cr>", 'close_list': "\<esc>", 'clear_char': "\<bs>"},
        \'list_mappings_projects': {'prev_view': "\<s-tab>", 'next_view': "\<tab>"},
        \'list_mappings_search_files': {'open_split': "\<c-s>"},
        \}
  let user = {
        \'list_mappings': {'open': 'o', 'extra': 'e'},
        \'list_mappings_projects': {'next_view': 'n'},
        \}

  let result = s:ConfigCall('MergeUserConfigIntoDefault', user, default)

  " User keys win, default keys survive, unknown nested keys are dropped
  call assert_equal({'open': 'o', 'close_list': "\<esc>", 'clear_char': "\<bs>"},
        \ result.list_mappings)
  call assert_equal({'prev_view': "\<s-tab>", 'next_view': 'n'},
        \ result.list_mappings_projects)
  " Untouched nested dicts keep their defaults
  call assert_equal({'open_split': "\<c-s>"}, result.list_mappings_search_files)
endfunction

function! Test_MergeUserConfigIntoDefault_against_real_defaults()
  let default = deepcopy(Helper_ScriptVar(s:config_file, 'default'))
  let user = {
        \'list_mappings_find_in_files': {'replace_confirm': "\<c-x>"},
        \'git_local_changes_mappings': {'commit': 'C'},
        \}

  let result = s:ConfigCall('MergeUserConfigIntoDefault', user, default)

  call assert_equal("\<c-x>", result.list_mappings_find_in_files.replace_confirm)
  call assert_equal("\<c-s>", result.list_mappings_find_in_files.open_split)
  call assert_equal('C', result.git_local_changes_mappings.commit)
  call assert_equal('p', result.git_local_changes_mappings.push)
  call assert_equal("\<cr>", result.list_mappings.open)
endfunction

" ---------------------------------------------------------------- add args

function! Test_GetAddArgs_legacy_json_option()
  let [path, option] = s:Call('GetAddArgs', '~/repo, {"note": "legacy note"}')
  call assert_equal('~/repo', path)
  call assert_equal({'note': 'legacy note'}, option)

  let [path, option] = s:Call('GetAddArgs', '~/repo,{"note":"x","other":1}')
  call assert_equal('~/repo', path)
  call assert_equal({'note': 'x', 'other': 1}, option)
endfunction

function! Test_GetAddArgs_new_quoted_note()
  let [path, option] = s:Call('GetAddArgs', '~/repo "my note"')
  call assert_equal('~/repo', path)
  call assert_equal({'note': 'my note'}, option)

  let [path, option] = s:Call('GetAddArgs', "~/repo 'single quoted'")
  call assert_equal('~/repo', path)
  call assert_equal({'note': 'single quoted'}, option)
endfunction

function! Test_GetAddArgs_path_only()
  let [path, option] = s:Call('GetAddArgs', '~/repo')
  call assert_equal('~/repo', path)
  call assert_equal({'note': ''}, option)

  let [path, option] = s:Call('GetAddArgs', '/path with space/repo')
  call assert_equal('/path with space/repo', path)
  call assert_equal({'note': ''}, option)
endfunction

" ---------------------------------------------------------------- shell

function! Test_RunShellCmd_handles_project_path_with_spaces()
  let dir = Helper_TmpDir('dir with space')
  call writefile(['x'], dir.'/marker.txt')

  let saved = $vim_project
  let $vim_project = dir
  try
    let output = project#RunShellCmd('ls')
    call assert_equal(['marker.txt'], output)
    call assert_equal(0, v:shell_error)
  finally
    let $vim_project = saved
  endtry
endfunction

function! Test_RunShellCmd_returns_empty_list_on_error()
  let saved = $vim_project
  let $vim_project = Helper_TmpDir('shell-error')
  try
    let output = project#RunShellCmd('exit 3', 0)
    call assert_equal([], output)
    call assert_notequal(0, v:shell_error)
  finally
    let $vim_project = saved
  endtry
endfunction

" ---------------------------------------------------------------- buffer cleanup

" Regression: a lost literal CR once split '%s/^M$//g' into two lines, and
" the stray '$//g' searched for the last search pattern, raising E486
" whenever git diffs were shown after searching for something absent.
function! Test_RemoveEmptyLines_strips_CR_and_ignores_last_search()
  let saved_search = @/
  let @/ = 'vim_project_pattern_that_is_never_present'
  new
  try
    call setline(1, ["a\r", 'b', "c\r"])
    call project#RemoveEmptyLines()
    call assert_equal(['a', 'b', 'c'], getline(1, '$'))

    " No CR at all must not raise either
    call project#RemoveEmptyLines()
    call assert_equal(['a', 'b', 'c'], getline(1, '$'))
  finally
    bwipeout!
    let @/ = saved_search
  endtry
endfunction

function! Test_autoload_sources_have_no_stray_carriage_returns()
  for file in glob(g:vim_project_test_root.'/autoload/**/*.vim', 0, 1)
        \ + glob(g:vim_project_test_root.'/plugin/*.vim', 0, 1)
    let crs = filter(readfile(file, 'b'), {_, line -> line =~ "\r"})
    call assert_equal([], crs, 'CR byte in '.file)
  endfor
endfunction

" ---------------------------------------------------------------- file mappings

function! Test_file_mappings_use_configured_prefix_and_unmap()
  let config = project#config#All()
  let saved = [config.file_mappings, config.file_mappings_prefix, config.file_open_types]
  let config.file_mappings = {'z': 'README.md'}
  let config.file_mappings_prefix = ',p'
  let config.file_open_types = {'': 'edit', 'v': 'vsplit'}
  try
    call s:Call('MapFile')
    call assert_match('OpenFile("edit", "README.md")', maparg(',pz', 'n'))
    call assert_match('OpenFile("vsplit", "README.md")', maparg(',pvz', 'n'))
    " The mark jump stays free
    call assert_equal('', maparg("'z", 'n'))

    call s:Call('UnmapFile')
    call assert_equal('', maparg(',pz', 'n'))
    call assert_equal('', maparg(',pvz', 'n'))
  finally
    let [config.file_mappings, config.file_mappings_prefix, config.file_open_types] = saved
    call s:Call('UnmapFile')
  endtry
endfunction

function! Test_file_mappings_default_prefix_is_quote()
  let config = project#config#All()
  let saved = [config.file_mappings, config.file_open_types]
  let config.file_mappings = {'z': 'README.md'}
  let config.file_open_types = {'': 'edit'}
  try
    call assert_equal("'", config.file_mappings_prefix)
    call s:Call('MapFile')
    call assert_match('README.md', maparg("'z", 'n'))
  finally
    let [config.file_mappings, config.file_open_types] = saved
    call s:Call('UnmapFile')
  endtry
endfunction

" ---------------------------------------------------------------- rename args

function! Test_SplitQuotedArgs()
  call assert_equal(['old', 'new'], s:Call('SplitQuotedArgs', 'old new'))
  call assert_equal(['my proj', 'new'], s:Call('SplitQuotedArgs', '"my proj" new'))
  call assert_equal(['my proj', 'new name'], s:Call('SplitQuotedArgs', "'my proj' 'new name'"))
  call assert_equal(['my proj', 'new'], s:Call('SplitQuotedArgs', 'my\ proj new'))
  call assert_equal(['a', 'b', 'c'], s:Call('SplitQuotedArgs', '  a  b c '))
  call assert_equal(['', 'x'], s:Call('SplitQuotedArgs', '"" x'))
  call assert_equal([], s:Call('SplitQuotedArgs', ''))
endfunction

function! Test_ParseRenameArgs_matches_existing_name_with_spaces()
  let projects = project#GetProjects()
  call add(projects, {'name': 'my proj', 'fullpath': '/tmp/my proj'})
  call add(projects, {'name': 'my', 'fullpath': '/tmp/my'})
  try
    " Longest existing name wins, as inserted by completion
    call assert_equal(['my proj', 'renamed'], s:Call('ParseRenameArgs', 'my proj renamed'))
    call assert_equal(['my', 'other'], s:Call('ParseRenameArgs', 'my other'))
    " Quoted input is parsed as is
    call assert_equal(['my proj', 'a b'], s:Call('ParseRenameArgs', '"my proj" "a b"'))
  finally
    call filter(projects, {_, p -> p.fullpath !~# '^/tmp/my'})
  endtry
endfunction

function! Test_RenameProjectByName_warns_on_bad_args()
  messages clear
  call project#RenameProjectByName('only-one-name')
  call assert_match('Usage: ProjectRename', execute('messages'))
  messages clear
  call project#RenameProjectByName('no-such-project new')
  call assert_match('Project not found: \[no-such-project\]', execute('messages'))
endfunction

" ---------------------------------------------------------------- loading

function! Test_SourcePluginConfigFiles_skips_duplicate_projects()
  let dir = Helper_TmpDir('dup-project')
  let add_file = expand(project#config#Get('config_home')).'/project.add.vim'
  let saved = filereadable(add_file) ? readfile(add_file) : []
  let projects = project#GetProjects()
  let before = len(projects)
  call writefile(['Project '.dir, 'Project '.dir.'/', 'Project '.dir], add_file)
  try
    call s:Call('SourcePluginConfigFiles')
    let matches = filter(copy(projects), {_, p -> p.fullpath ==# dir})
    call assert_equal(1, len(matches))
    call assert_equal(before + 1, len(projects))
  finally
    call filter(projects, {_, p -> p.fullpath !=# dir})
    call writefile(saved, add_file)
  endtry
endfunction

" ---------------------------------------------------------------- switching

function! Test_OpenProject_keeps_unsaved_changes()
  let base = Helper_TmpDir('switch')
  call mkdir(base.'/A')
  call mkdir(base.'/B')
  call writefile(['original'], base.'/A/a.txt')
  let a = {'name': 'A', 'path': base, 'fullpath': base.'/A', 'note': '', 'option': {}}
  let b = {'name': 'B', 'path': base, 'fullpath': base.'/B', 'note': '', 'option': {}}
  set hidden
  try
    call project#OpenProject(a)
    execute 'edit' fnameescape(base.'/A/a.txt')
    call setline(1, 'unsaved edit')
    let nr = bufnr('%')
    enew

    messages clear
    call assert_equal(1, project#OpenProject(b))
    " Still in A, the edit is kept and the user is told why
    call assert_equal('A', g:vim_project.name)
    call assert_true(bufloaded(nr))
    call assert_equal(['unsaved edit'], getbufline(nr, 1, '$'))
    call assert_match('Save or discard changes before switching project: .*a\.txt', execute('messages'))

    " Once saved, switching works
    call setbufvar(nr, '&modified', 0)
    call project#OpenProject(b)
    call assert_equal('B', g:vim_project.name)
  finally
    call project#QuitProject()
    set nohidden
    silent! %bwipeout!
  endtry
endfunction

" ---------------------------------------------------------------- special paths

" '#' and '%' are expanded by Ex commands unless escaped
function! Test_project_with_special_characters_in_path()
  let base = Helper_TmpDir('special-path')
  let dir = base.'/my proj#1%x'
  call mkdir(dir)
  call writefile(['content'], dir.'/c.txt')
  let project = {'name': 'my proj#1%x', 'path': base, 'fullpath': dir, 'note': '', 'option': {}}
  let saved_config = deepcopy(g:vim_project_config)
  let g:vim_project_config.use_session = 1
  let g:vim_project_config.use_viminfo = 1
  try
    call s:Call('InitProjectConfig', project)
    messages clear
    call project#OpenProject(project)
    call assert_equal(resolve(dir), resolve(getcwd()))

    " Open a file of the project, then save the session by quitting
    call s:Call('OpenFile', 'edit', 'c.txt')
    call assert_equal('c.txt', expand('%:t'))
    call project#QuitProject()
    let config_dir = project#GetProjectConfigPath(expand(g:vim_project_config.config_home), project)
    " Without a git branch the session is named '.vim'
    call assert_notequal([], (isdirectory(config_dir.'/sessions') ? readdir(config_dir.'/sessions') : []), 'session saved')

    " Reopening restores the session
    enew
    silent! %bwipeout!
    call project#OpenProject(project)
    call assert_equal('c.txt', expand('%:t'))

    " Writing init.vim reloads the config
    ProjectConfig
    call assert_equal(resolve(config_dir.'/init.vim'), resolve(expand('%:p')))
    messages clear
    write
    call assert_match('Config Reloaded', execute('messages'))
    tabclose

    call assert_notmatch('E\d\+:', execute('messages'))
  finally
    let g:vim_project_config = saved_config
    call project#QuitProject()
    silent! %bwipeout!
  endtry
endfunction

" ---------------------------------------------------------------- viminfo

function! s:History(type)
  let last = histnr(a:type)
  return last < 1 ? [] : filter(map(range(1, last), {_, nr -> histget(a:type, nr)}), '!empty(v:val)')
endfunction

" Issue #9: with use_viminfo, history of one project must not leak into
" another, in memory or in its viminfo / shada file
function! Test_use_viminfo_keeps_history_per_project()
  let base = Helper_TmpDir('viminfo')
  call mkdir(base.'/A')
  call mkdir(base.'/B')
  let a = {'name': 'A', 'path': base, 'fullpath': base.'/A', 'note': '', 'option': {}}
  let b = {'name': 'B', 'path': base, 'fullpath': base.'/B', 'note': '', 'option': {}}
  let saved_config = deepcopy(g:vim_project_config)
  let g:vim_project_config.use_viminfo = 1
  " The runner starts Vim with -i NONE, which also turns off :wviminfo
  let saved_viminfofile = exists('+viminfofile') ? &viminfofile : ''
  if exists('+viminfofile')
    set viminfofile=
  endif
  try
    call s:Call('InitProjectConfig', a)
    call s:Call('InitProjectConfig', b)

    call project#OpenProject(a)
    call histadd('cmd', 'only-in-A')
    call histadd('search', 'search-in-A')

    call project#OpenProject(b)
    call assert_equal(-1, index(s:History('cmd'), 'only-in-A'), 'cmd history of A in B')
    call assert_equal(-1, index(s:History('search'), 'search-in-A'), 'search history of A in B')
    call histadd('cmd', 'only-in-B')

    call project#OpenProject(a)
    call assert_notequal(-1, index(s:History('cmd'), 'only-in-A'), 'A gets its history back')
    call assert_equal(-1, index(s:History('cmd'), 'only-in-B'), 'cmd history of B in A')

    " B's file has none of A's history
    call project#QuitProject()
    let b_dir = project#GetProjectConfigPath(expand(g:vim_project_config.config_home), b)
    let b_file = glob(b_dir.'/viminfo/*', 1, 1) + glob(b_dir.'/viminfo/.*', 1, 1)
    call filter(b_file, 'filereadable(v:val)')
    call assert_equal(1, len(b_file))
    call assert_notmatch('only-in-A', join(readfile(b_file[0], 'b'), "\n"))
  finally
    let g:vim_project_config = saved_config
    call project#QuitProject()
    if exists('+viminfofile')
      let &viminfofile = saved_viminfofile
    endif
  endtry
endfunction
