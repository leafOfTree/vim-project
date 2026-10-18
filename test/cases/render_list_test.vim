" Tests for project#RenderList error recovery.
let s:list_buffer = 'vim_project_list'

function! s:ThrowingInit(input)
  throw 'vim-project-test: init failed'
endfunction

function! s:Noop(...)
endfunction

function! Test_RenderList_restores_options_and_closes_list_when_init_throws()
  let laststatus_save = project#GetVariable('laststatus_save')
  let ruler_save = project#GetVariable('ruler_save')
  let &laststatus = laststatus_save
  let &ruler = ruler_save
  let windows_before = winnr('$')

  call project#PrepareListBuffer('Test:', 'TEST')
  " Sanity check: the list window is open and changed the options
  call assert_notequal(-1, bufwinnr(s:list_buffer))
  call assert_equal(0, &laststatus)
  call assert_equal(0, &ruler)

  call project#RenderList(function('s:ThrowingInit'), function('s:Noop'), function('s:Noop'))

  call assert_equal(laststatus_save, &laststatus, 'laststatus restored')
  call assert_equal(ruler_save, &ruler, 'ruler restored')
  call assert_equal(-1, bufwinnr(s:list_buffer), 'list window closed')
  call assert_equal(windows_before, winnr('$'), 'window count restored')
  call assert_match('init failed', execute('messages'), 'error reported')

  " List state was reset so the next list starts clean
  call assert_false(project#Exist('list_type'))
  call assert_false(project#Exist('prefix'))
endfunction

function! Test_RenderList_init_error_does_not_leak_into_next_list()
  call project#PrepareListBuffer('Test:', 'TEST')
  call project#RenderList(function('s:ThrowingInit'), function('s:Noop'), function('s:Noop'))

  " Opening the list again must work normally
  call project#PrepareListBuffer('Test again:', 'TEST')
  call assert_notequal(-1, bufwinnr(s:list_buffer))
  call assert_equal('TEST', project#GetVariable('list_type'))
  call project#RenderList(function('s:ThrowingInit'), function('s:Noop'), function('s:Noop'))
  call assert_equal(-1, bufwinnr(s:list_buffer))
endfunction
