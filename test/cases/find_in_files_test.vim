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
