" Tests for project#list#Open error recovery.
let s:list_buffer = 'vim_project_list'

function! s:ThrowingInit(input)
  throw 'vim-project-test: init failed'
endfunction

function! s:Noop(...)
endfunction

function! s:Spec(prompt)
  return {
        \'type': 'TEST',
        \'prompt': a:prompt,
        \'Init': function('s:ThrowingInit'),
        \'Update': function('s:Noop'),
        \'Open': function('s:Noop'),
        \}
endfunction

function! Test_RenderList_restores_options_and_closes_list_when_init_throws()
  set laststatus=2
  set ruler
  let windows_before = winnr('$')

  " Init throws inside project#list#Open, which opens and closes the list
  call project#list#Open(s:Spec('Test:'))

  call assert_equal(2, &laststatus, 'laststatus restored')
  call assert_equal(1, &ruler, 'ruler restored')
  call assert_equal(-1, bufwinnr(s:list_buffer), 'list window closed')
  call assert_equal(windows_before, winnr('$'), 'window count restored')
  call assert_match('init failed', execute('messages'), 'error reported')

  " List state was reset so the next list starts clean
  let state = project#list#State()
  call assert_false(has_key(state, 'list'))
  call assert_false(has_key(state, 'input'))
  " A failed list must not leave history behind
  call assert_equal({}, project#list#GetHistory('TEST'))
endfunction

function! Test_RenderList_init_error_does_not_leak_into_next_list()
  set laststatus=2
  call project#list#Open(s:Spec('Test:'))
  call assert_equal(-1, bufwinnr(s:list_buffer))

  " Opening the list again must work normally and recover again
  call project#list#Open(s:Spec('Test again:'))
  call assert_equal(-1, bufwinnr(s:list_buffer))
  call assert_equal(2, &laststatus)
endfunction
