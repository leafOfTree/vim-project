" Tests for autoload/project/find_in_files.vim helpers.
let s:file = 'autoload/project/find_in_files.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

" Run a:Fn with the given include/exclude lists, restoring the originals.
function! s:WithIncludeExclude(include, exclude, Fn)
  let config = project#config#All()
  let saved_include = config.find_in_files_include
  let saved_exclude = config.find_in_files_exclude
  let config.find_in_files_include = a:include
  let config.find_in_files_exclude = a:exclude
  try
    return a:Fn()
  finally
    let config.find_in_files_include = saved_include
    let config.find_in_files_exclude = saved_exclude
  endtry
endfunction

" ---------------------------------------------------------------- input

function! Test_ParseInput_search_and_replace()
  call assert_equal(['foo', 'bar'], s:Call('ParseInput', 'foo => bar'))
  call assert_equal(['foo bar', 'baz qux'], s:Call('ParseInput', 'foo bar => baz qux'))
endfunction

function! Test_ParseInput_search_only()
  call assert_equal(['foo', ''], s:Call('ParseInput', 'foo'))
  " A trailing separator means "replace with nothing yet"
  call assert_equal(['foo', ''], s:Call('ParseInput', 'foo => '))
  call assert_equal(['', ''], s:Call('ParseInput', ''))
endfunction

function! Test_ParseInput_multiple_separators_keep_whole_input()
  call assert_equal(['a => b => c', ''], s:Call('ParseInput', 'a => b => c'))
endfunction

function! Test_ParseInput_ignores_arrow_without_spaces()
  call assert_equal(['a=>b', ''], s:Call('ParseInput', 'a=>b'))
endfunction

" ---------------------------------------------------------------- flags

function! Test_GetSearchFlags()
  call assert_equal('', s:Call('GetSearchFlags', 'foo'))
  call assert_equal('C', s:Call('GetSearchFlags', '\Cfoo'))
  call assert_equal('E', s:Call('GetSearchFlags', '\Efoo'))
  call assert_equal('CE', s:Call('GetSearchFlags', '\C\Efoo'))
  call assert_equal('CE', s:Call('GetSearchFlags', '\E\Cfoo'))
  call assert_equal('C', s:Call('GetSearchFlags', 'foo\C'))
endfunction

function! Test_RemoveSearchFlags()
  call assert_equal('foo', s:Call('RemoveSearchFlags', 'foo'))
  call assert_equal('foo', s:Call('RemoveSearchFlags', '\Cfoo'))
  call assert_equal('foo', s:Call('RemoveSearchFlags', '\C\Efoo'))
  call assert_equal('foo bar', s:Call('RemoveSearchFlags', '\Efoo\C bar'))
  " A dangling backslash while typing is dropped, an escaped one is kept
  call assert_equal('foo', s:Call('RemoveSearchFlags', 'foo\'))
  call assert_equal('foo\\', s:Call('RemoveSearchFlags', 'foo\\'))
endfunction

" ---------------------------------------------------------------- pattern

function! Test_GetSearchPattern_defaults_to_ignorecase_verynomagic()
  call assert_equal('\c\Vfoo', s:Call('GetSearchPattern', 'foo'))
endfunction

function! Test_GetSearchPattern_case_sensitive_flag()
  call assert_equal('\C\Vfoo', s:Call('GetSearchPattern', '\Cfoo'))
endfunction

function! Test_GetSearchPattern_regexp_flag()
  call assert_equal('\c\vfo+', s:Call('GetSearchPattern', '\Efo+'))
  call assert_equal('\C\vfo+', s:Call('GetSearchPattern', '\C\Efo+'))
endfunction

function! Test_GetSearchPattern_escapes_slash_and_word_boundary()
  call assert_equal('\c\Va\/b', s:Call('GetSearchPattern', 'a/b'))
  " \b (rg/ag style) becomes \W so the Vim highlight pattern stays valid
  call assert_equal('\c\vfoo\Wbar', s:Call('GetSearchPattern', '\Efoo\bbar'))
endfunction

" ---------------------------------------------------------------- grouping

function! Test_GetGroupedList_inserts_file_headers()
  let list = [
        \{'file': 'a.vim', 'lnum': 1, 'line': 'one'},
        \{'file': 'a.vim', 'lnum': 5, 'line': 'two'},
        \{'file': 'b.vim', 'lnum': 2, 'line': 'three'},
        \]
  let result = s:Call('GetGroupedList', list)

  call assert_equal(5, len(result))
  call assert_equal({'file': 'a.vim'}, result[0])
  call assert_equal(list[0], result[1])
  call assert_equal(list[1], result[2])
  call assert_equal({'file': 'b.vim'}, result[3])
  call assert_equal(list[2], result[4])
endfunction

function! Test_GetGroupedList_propagates_more_flag()
  let list = [
        \{'file': 'a.vim', 'lnum': 1, 'line': 'one', 'more': 1},
        \{'file': 'a.vim', 'lnum': 2, 'line': 'two'},
        \]
  let result = s:Call('GetGroupedList', list)
  call assert_equal(1, result[0].more)
  call assert_equal('a.vim', result[0].file)
endfunction

function! Test_GetGroupedList_empty()
  call assert_equal([], s:Call('GetGroupedList', []))
endfunction

" ---------------------------------------------------------------- commands

function! Test_GetRgCmd_include_exclude_and_fixed_strings()
  let cmd = s:WithIncludeExclude(['src', 'lib'], ['.git', 'node_modules'],
        \ {-> s:Call('GetRgCmd', "'pat'", '')})
  call assert_match('^rg ', cmd)
  call Helper_AssertContains(cmd, '-g "{src/**,lib/**}"')
  call Helper_AssertContains(cmd, '-g "!{.git,node_modules}"')
  call Helper_AssertContains(cmd, '--fixed-strings')
  call Helper_AssertContains(cmd, '--ignore-case')
  call Helper_AssertContains(cmd, '--line-number')
  call assert_match(" -- 'pat'$", cmd)
endfunction

function! Test_GetRgCmd_flags_switch_to_regexp_and_case_sensitive()
  let cmd = s:WithIncludeExclude(['src'], ['.git'],
        \ {-> s:Call('GetRgCmd', "'pat'", 'CE')})
  call Helper_AssertNotContains(cmd, '--fixed-strings')
  call Helper_AssertNotContains(cmd, '--ignore-case')
endfunction

function! Test_GetRgCmd_dot_include_means_everything()
  let cmd = s:WithIncludeExclude(['.'], ['.git'],
        \ {-> s:Call('GetRgCmd', "'pat'", '')})
  call Helper_AssertContains(cmd, '-g "{**}"')
  call Helper_AssertNotContains(cmd, './**')
endfunction

function! Test_GetAgCmd_include_exclude_and_fixed_strings()
  let cmd = s:WithIncludeExclude(['src', 'lib'], ['.git', 'node_modules'],
        \ {-> s:Call('GetAgCmd', "'pat'", '')})
  call assert_match('^ag ', cmd)
  call Helper_AssertContains(cmd, '--ignore-dir .git --ignore-dir node_modules')
  call Helper_AssertContains(cmd, '--fixed-strings')
  call Helper_AssertContains(cmd, '--ignore-case')
  " The pattern comes before the paths
  call assert_match(" -- 'pat' src lib$", cmd)
endfunction

function! Test_GetAgCmd_flags()
  let cmd = s:WithIncludeExclude(['src'], ['.git'],
        \ {-> s:Call('GetAgCmd', "'pat'", 'CE')})
  call Helper_AssertNotContains(cmd, '--fixed-strings')
  call Helper_AssertNotContains(cmd, '--ignore-case')
  call Helper_AssertContains(cmd, '--case-sensitive')
endfunction

function! Test_GetGrepCmd_include_exclude_and_fixed_strings()
  let cmd = s:WithIncludeExclude(['src', 'lib'], ['.git', 'node_modules'],
        \ {-> s:Call('GetGrepCmd', "'pat'", '')})
  call assert_match('^grep ', cmd)
  call Helper_AssertContains(cmd, '--exclude-dir .git --exclude-dir node_modules')
  call Helper_AssertContains(cmd, '--fixed-strings')
  call Helper_AssertNotContains(cmd, '--extended-regexp')
  call Helper_AssertContains(cmd, '--ignore-case')
  call Helper_AssertContains(cmd, '--recursive')
  call Helper_AssertContains(cmd, '--line-number')
  " The pattern comes before the paths
  call assert_match(" -e 'pat' -- src lib$", cmd)
endfunction

function! Test_GetGrepCmd_regexp_flag_uses_extended_regexp()
  let cmd = s:WithIncludeExclude(['src'], ['.git'],
        \ {-> s:Call('GetGrepCmd', "'pat'", 'E')})
  call Helper_AssertContains(cmd, '--extended-regexp')
  call Helper_AssertNotContains(cmd, '--fixed-strings')
  call Helper_AssertContains(cmd, '--ignore-case')
endfunction

function! Test_GetGrepCmd_case_sensitive_flag()
  let cmd = s:WithIncludeExclude(['src'], ['.git'],
        \ {-> s:Call('GetGrepCmd', "'pat'", 'C')})
  call Helper_AssertNotContains(cmd, '--ignore-case')
  call Helper_AssertContains(cmd, '--fixed-strings')
endfunction

function! Test_GetGrepCmd_empty_include_searches_current_dir()
  let cmd = s:WithIncludeExclude([], ['.git'],
        \ {-> s:Call('GetGrepCmd', "'pat'", '')})
  call assert_match(" -e 'pat' -- \\.$", cmd)
endfunction

function! Test_grep_commands_do_not_mutate_config_lists()
  let include = ['src']
  let exclude = ['.git']
  call s:WithIncludeExclude(include, exclude, {-> s:Call('GetRgCmd', "'p'", '')})
  call s:WithIncludeExclude(include, exclude, {-> s:Call('GetAgCmd', "'p'", '')})
  call s:WithIncludeExclude(include, exclude, {-> s:Call('GetGrepCmd', "'p'", '')})
  call assert_equal(['src'], include)
  call assert_equal(['.git'], exclude)
endfunction

" ---------------------------------------------------------------- replace

function! Test_ParseGrepLine_keeps_colons_in_text()
  call assert_equal({'file': 'src/a.rs', 'lnum': '3', 'line': 'use std::io;'},
        \ s:Call('ParseGrepLine', 'src/a.rs:3:use std::io;'))
  call assert_equal({'file': 'a.vim', 'lnum': '7', 'line': ':foo::'},
        \ s:Call('ParseGrepLine', 'a.vim:7::foo::'))
  " A non-match line, such as an error, is kept for display with lnum 0
  let item = s:Call('ParseGrepLine', 'Error: too many')
  call assert_equal(0, item.lnum)
endfunction

function! Test_GetReplacedLine_inserts_replacement_literally()
  let pattern = s:Call('GetSearchPattern', 'foo')
  call assert_equal('a&b bar', s:Call('GetReplacedLine', 'foo bar', pattern, 'a&b', 0))
  call assert_equal('\1~ bar', s:Call('GetReplacedLine', 'foo bar', pattern, '\1~', 0))
  " Case-insensitive by default, every occurrence
  call assert_equal('x x', s:Call('GetReplacedLine', 'foo FOO', pattern, 'x', 0))
  " add=1 keeps the match before the replacement, for display
  call assert_equal('foox bar', s:Call('GetReplacedLine', 'foo bar', pattern, 'x', 1))
endfunction

function! s:Item(file, lnum, line)
  return {'file': a:file, 'lnum': string(a:lnum), 'line': a:line}
endfunction

" Write a:lines in binary mode, so "\r" and a missing final newline are kept
function! s:WriteBinary(dir, name, lines)
  call writefile(a:lines, a:dir.'/'.a:name, 'b')
endfunction

function! Test_ReplaceInFiles_is_safe()
  let dir = Helper_TmpDir('replace')
  let saved_project = $vim_project
  let $vim_project = dir

  call s:WriteBinary(dir, 'multi.txt', ['foo 1', 'bar', 'foo 2', ''])
  call s:WriteBinary(dir, 'crlf.txt', ["foo\r", "keep\r", ''])
  call s:WriteBinary(dir, 'noeol.txt', ['foo'])
  call s:WriteBinary(dir, 'stale.txt', ['foo changed', ''])
  call s:WriteBinary(dir, 'unsaved.txt', ['foo', ''])
  call s:WriteBinary(dir, 'loaded.txt', ['foo', ''])
  " Before Vim 8.2.3510 and Neovim 0.7 a change within about 2 seconds isn't
  " detected, as file times are compared in seconds
  if (has('nvim') ? !has('nvim-0.7') : !has('patch-8.2.3510')) && executable('touch')
    call system('touch -d "1 hour ago" '.shellescape(dir).'/*.txt')
  endif

  " unsaved.txt has unsaved edits, loaded.txt is open without changes
  execute 'edit' fnameescape(dir.'/unsaved.txt')
  call setline(1, 'edited in buffer')
  let unsaved_bufnr = bufnr('%')
  execute 'split' fnameescape(dir.'/loaded.txt')
  let loaded_bufnr = bufnr('%')
  " ! hides the modified buffer instead of refusing (Vim without 'hidden')
  only!

  let list = [
        \{'file': 'multi.txt'},
        \s:Item('multi.txt', 1, 'foo 1'),
        \s:Item('multi.txt', 3, 'foo 2'),
        \{'file': 'crlf.txt'},
        \s:Item('crlf.txt', 1, 'foo'),
        \{'file': 'noeol.txt'},
        \s:Item('noeol.txt', 1, 'foo'),
        \{'file': 'stale.txt'},
        \s:Item('stale.txt', 1, 'foo'),
        \s:Item('stale.txt', 9, 'foo'),
        \{'file': 'unsaved.txt'},
        \s:Item('unsaved.txt', 1, 'foo'),
        \{'file': 'loaded.txt'},
        \s:Item('loaded.txt', 1, 'foo'),
        \{'file': 'missing.txt'},
        \s:Item('missing.txt', 1, 'foo'),
        \]

  try
    let groups = s:Call('GroupLineItemsByFile', list)
    call assert_equal(['multi.txt', 'crlf.txt', 'noeol.txt', 'stale.txt',
          \ 'unsaved.txt', 'loaded.txt', 'missing.txt'],
          \ map(copy(groups), {_, g -> g.file}))
    call assert_equal(2, len(groups[0].items))

    let pattern = s:Call('GetSearchPattern', 'foo')
    let result = s:Call('ReplaceInFiles', groups, pattern, 'a&b')
    call s:Call('ReloadChangedBuffers', result.changed)

    call assert_equal(['a&b 1', 'bar', 'a&b 2', ''], readfile(dir.'/multi.txt', 'b'))
    " CRLF line endings survive
    call assert_equal(["a&b\r", "keep\r", ''], readfile(dir.'/crlf.txt', 'b'))
    " No final newline is added
    call assert_equal(['a&b'], readfile(dir.'/noeol.txt', 'b'))
    " A line that changed since the search is left alone
    call assert_equal(['foo changed', ''], readfile(dir.'/stale.txt', 'b'))
    call assert_equal(['stale.txt:1', 'stale.txt:9', 'missing.txt:1'], result.stale)
    " A file with unsaved buffer changes is not written; the edit survives
    call assert_equal(['foo', ''], readfile(dir.'/unsaved.txt', 'b'))
    call assert_equal(['unsaved.txt'], result.unsaved)
    call assert_equal(['edited in buffer'], getbufline(unsaved_bufnr, 1, '$'))
    " An unmodified open buffer is reloaded with the new content
    call assert_equal(['a&b'], getbufline(loaded_bufnr, 1, '$'))

    call assert_equal(5, result.lines)
    call assert_equal(4, len(result.changed))
    call assert_equal([], result.failed)
  finally
    let $vim_project = saved_project
    execute 'silent! bwipeout!' unsaved_bufnr
    execute 'silent! bwipeout!' loaded_bufnr
  endtry
endfunction

" ---------------------------------------------------------------- separator

function! s:WithSeparator(separator, Fn)
  let config = project#config#All()
  let saved = config.find_replace_separator
  let config.find_replace_separator = a:separator
  try
    return a:Fn()
  finally
    let config.find_replace_separator = saved
  endtry
endfunction

function! Test_ParseInput_custom_separator_allows_searching_default_one()
  call s:WithSeparator(' ->> ', {->
        \ assert_equal(['a => b', 'c'], s:Call('ParseInput', 'a => b ->> c'))})
  call s:WithSeparator(' ->> ', {->
        \ assert_equal(['x => y', ''], s:Call('ParseInput', 'x => y'))})
endfunction

function! Test_ParseInput_separator_is_matched_literally()
  " '|' and '.' would be regexp syntax if used as a pattern
  call s:WithSeparator(' |.| ', {->
        \ assert_equal(['foo', 'bar'], s:Call('ParseInput', 'foo |.| bar'))})
  call s:WithSeparator(' |.| ', {->
        \ assert_equal(['foo |x| bar', ''], s:Call('ParseInput', 'foo |x| bar'))})
endfunction

function! Test_OnReplacePrompt_appends_configured_separator_once()
  let state = {'user_input': 'foo'}
  call s:WithSeparator(' ->> ', {-> s:Call('OnReplacePrompt', state)})
  call assert_equal('foo ->> ', state.user_input)
  call s:WithSeparator(' ->> ', {-> s:Call('OnReplacePrompt', state)})
  call assert_equal('foo ->> ', state.user_input)
endfunction

function! Test_GetSeparator_falls_back_when_empty()
  call s:WithSeparator('', {-> assert_equal(' => ', s:Call('GetSeparator'))})
endfunction

" ---------------------------------------------------------------- background grep

function! s:WaitGrep()
  call s:Call('WaitGrep')
  sleep 20m
endfunction

function! s:Lines()
  let list = Helper_ScriptVar(s:file, 'list')
  return filter(copy(list), {_, item -> has_key(item, 'line')})
endfunction

function! s:BackgroundGrep(dir)
  if !s:Call('CanGrepInBackground', 'needle')
    return
  endif
  let show_max = Helper_ScriptVar(s:file, 'find_in_files_show_max')

  " Results are grouped by file
  call s:Call('StartGrep', 'needle', 0)
  call s:WaitGrep()
  let list = Helper_ScriptVar(s:file, 'list')
  call assert_equal(['a.txt', 'a.txt'], map(filter(copy(list), {_, i -> has_key(i, 'line')}), 'v:val.file'))
  call assert_equal({'file': 'a.txt'}, list[0])

  " A normal search stops once it has more than can be shown
  call s:Call('StartGrep', 'many', 0)
  call s:WaitGrep()
  let lines = s:Lines()
  call assert_true(len(lines) <= show_max + 1, 'kept '.len(lines))
  call assert_equal(1, get(Helper_ScriptVar(s:file, 'list')[0], 'more', 0))

  " Replace mode keeps every match
  call s:Call('StartGrep', 'many', 1)
  call s:WaitGrep()
  call assert_equal(show_max * 2, len(s:Lines()))

  " A newer search wins over one still running
  call s:Call('StartGrep', 'many', 1)
  call s:Call('StartGrep', 'needle', 0)
  call s:WaitGrep()
  sleep 100m
  call assert_equal(2, len(s:Lines()))
  call assert_match('needle', s:Lines()[0].line)
endfunction

function! Test_StartGrep_runs_in_background()
  let dir = Helper_TmpDir('grep-background')
  call writefile(['a needle', 'nothing', 'needle again'], dir.'/a.txt')
  let show_max = Helper_ScriptVar(s:file, 'find_in_files_show_max')
  call writefile(map(range(show_max * 2), '"many ".v:val'), dir.'/many.txt')
  call s:WithIncludeExclude(['.'], [], function('s:WithProjectDir', [dir, function('s:BackgroundGrep', [dir])]))
endfunction

function! s:WithProjectDir(dir, Fn)
  let saved = $vim_project
  let $vim_project = a:dir
  try
    call a:Fn()
  finally
    call s:Call('StopGrep')
    let $vim_project = saved
  endtry
endfunction

" ---------------------------------------------------------------- real programs

" Run each available program for real: argument order mistakes only show
" up there (grep and ag take the first operand as the pattern)
function! s:SearchWith(program, search, flags)
  if a:program ==# 'vimgrep'
    let items = s:Call('RunVimGrep', a:search, a:flags, a:search)
  else
    let Cmd = Helper_Funcref(s:file, {'rg': 'GetRgCmd', 'ag': 'GetAgCmd', 'grep': 'GetGrepCmd'}[a:program])
    let output = project#RunShellCmd(Cmd(shellescape(a:search), a:flags), 0)
    let items = map(output, {_, line -> s:Call('ParseGrepLine', line)})
  endif
  return sort(map(items, {_, item -> item.file.':'.item.lnum.':'.item.line}))
endfunction

function! s:CheckPrograms(dir)
  for program in ['rg', 'ag', 'grep', 'vimgrep']
    if program !=# 'vimgrep' && !executable(program)
      continue
    endif
    call assert_equal(['a.txt:1:Needle here', 'a.txt:3:needle.*x', 'sub/b.txt:2:-needle- again'],
          \ s:SearchWith(program, 'needle', ''), program.' fixed, ignore case')
    call assert_equal(['sub/b.txt:2:-needle- again'],
          \ s:SearchWith(program, '-needle-', ''), program.' pattern starting with -')
    call assert_equal(['a.txt:1:Needle here'],
          \ s:SearchWith(program, 'Needle', 'C'), program.' match case')
    call assert_equal(['a.txt:3:needle.*x'],
          \ s:SearchWith(program, 'needle.*x', 'C'), program.' literal')
    call assert_equal(['a.txt:3:needle.*x', 'sub/b.txt:2:-needle- again'],
          \ s:SearchWith(program, 'needle.', 'CE'), program.' regexp')
    " Excluded directories are skipped
    call assert_equal([], s:SearchWith(program, 'hidden_in_excluded', ''), program.' exclude')
  endfor
endfunction

function! Test_grep_programs_find_matches_for_real()
  " A space in the path catches unescaped commands
  let dir = Helper_TmpDir('grep programs')
  call mkdir(dir.'/sub')
  call mkdir(dir.'/node_modules')
  call writefile(['Needle here', 'nothing', 'needle.*x'], dir.'/a.txt')
  call writefile(['nothing', '-needle- again'], dir.'/sub/b.txt')
  call writefile(['hidden_in_excluded'], dir.'/node_modules/c.txt')
  call s:WithIncludeExclude(['.'], ['node_modules'],
        \ function('s:WithProjectDir', [dir, function('s:CheckPrograms', [dir])]))
endfunction
