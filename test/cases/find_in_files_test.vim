" Tests for autoload/project/find_in_files.vim helpers.
let s:file = 'autoload/project/find_in_files.vim'

function! s:Call(name, ...)
  return Helper_Call(s:file, a:name, a:000)
endfunction

" Run a:Fn with the given include/exclude lists, restoring the originals.
function! s:WithIncludeExclude(include, exclude, Fn)
  let saved_include = project#GetVariable('find_in_files_include')
  let saved_exclude = project#GetVariable('find_in_files_exclude')
  call project#SetVariable('find_in_files_include', a:include)
  call project#SetVariable('find_in_files_exclude', a:exclude)
  try
    return a:Fn()
  finally
    call project#SetVariable('find_in_files_include', saved_include)
    call project#SetVariable('find_in_files_exclude', saved_exclude)
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
  call Helper_AssertContains(cmd, ' src lib ')
  call Helper_AssertContains(cmd, '--ignore-dir .git --ignore-dir node_modules')
  call Helper_AssertContains(cmd, '--fixed-strings')
  call Helper_AssertContains(cmd, '--ignore-case')
  call assert_match(" -- 'pat'$", cmd)
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
  call Helper_AssertContains(cmd, ' src lib ')
  call Helper_AssertContains(cmd, '--exclude-dir .git --exclude-dir node_modules')
  call Helper_AssertContains(cmd, '--fixed-strings')
  call Helper_AssertNotContains(cmd, '--extended-regexp')
  call Helper_AssertContains(cmd, '--ignore-case')
  call Helper_AssertContains(cmd, '--recursive')
  call Helper_AssertContains(cmd, '--line-number')
  call assert_match(" -- 'pat'$", cmd)
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
  call Helper_AssertContains(cmd, ' . --exclude-dir .git')
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
