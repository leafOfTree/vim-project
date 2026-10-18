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
