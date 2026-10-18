" Tests for autoload/project/list_projects.vim filtering and sorting.
let s:file = 'autoload/project/list_projects.vim'

function! s:Project(name, path, ...)
  return {'name': a:name, 'path': a:path, 'option': a:0 ? a:1 : {}}
endfunction

function! s:Filter(list, filter)
  return Helper_Call(s:file, 'FilterProjectsList', [deepcopy(a:list), a:filter])
endfunction

function! s:Names(list)
  return map(copy(a:list), {_, item -> item.name})
endfunction

" The list is rendered bottom-up: the LAST item is the default target, so
" better matches sort later.

function! Test_FilterProjectsList_name_matches_beat_note_and_path()
  let list = [
        \s:Project('other', '/x/'),
        \s:Project('by-path', '/abc/'),
        \s:Project('by-note', '/x/', {'note': 'abc note'}),
        \s:Project('abc', '/x/'),
        \]
  let result = s:Filter(list, 'abc')

  " When name or note matches exist, pure path matches are dropped
  call assert_equal(['by-note', 'abc'], s:Names(result))
  " Scoring must not leak bookkeeping keys into the project dicts
  call assert_false(has_key(result[0], '_match_type'))
endfunction

function! Test_FilterProjectsList_falls_back_to_path_matches()
  let list = [
        \s:Project('other', '/x/'),
        \s:Project('q', '/zz/'),
        \s:Project('kz', '/z/'),
        \]
  let result = s:Filter(list, 'zz')

  " path < full_path, so the full_path match ends up last
  call assert_equal(['q', 'kz'], s:Names(result))
endfunction

function! Test_FilterProjectsList_prefers_exact_then_earlier_match()
  let list = [
        \s:Project('abc', '/x/'),
        \s:Project('a-b', '/x/'),
        \s:Project('xab', '/x/'),
        \]
  let result = s:Filter(list, 'ab')

  " a-b only matches the fuzzy a.*b pattern (+10), xab matches at index 1,
  " abc matches at index 0 and wins
  call assert_equal(['a-b', 'xab', 'abc'], s:Names(result))
endfunction

function! Test_FilterProjectsList_same_index_prefers_shorter_name()
  let list = [
        \s:Project('abc', '/x/'),
        \s:Project('abcdef', '/x/'),
        \]
  let result = s:Filter(list, 'ab')
  call assert_equal(['abcdef', 'abc'], s:Names(result))
endfunction

function! Test_FilterProjectsList_fuzzy_match_is_case_sensitive_on_name()
  let list = [s:Project('ABC', '/x/'), s:Project('abc', '/x/')]
  let result = s:Filter(list, 'abc')
  call assert_equal(['abc'], s:Names(result))
endfunction

function! Test_FilterProjectsList_no_match_returns_empty()
  let list = [s:Project('abc', '/x/'), s:Project('def', '/y/', {'note': 'n'})]
  call assert_equal([], s:Filter(list, 'zzz'))
endfunction

function! Test_FilterProjectsList_empty_filter_matches_everything_by_name()
  let list = [s:Project('b', '/x/'), s:Project('a', '/y/')]
  let result = s:Filter(list, '')
  call assert_equal(['a', 'b'], sort(s:Names(result)))
endfunction

function! Test_FilterProjectsList_matches_path_with_home_as_tilde()
  let list = [s:Project('proj', expand('~').'/work/')]
  let result = s:Filter(list, '/w')
  call assert_equal(['proj'], s:Names(result))
endfunction

