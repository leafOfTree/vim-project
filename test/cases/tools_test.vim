" CI runs the tests twice per editor: with only the tools of the system
" (grep, find), so the fallbacks are tested, and with rg, ag and fd. Make
" sure each run really has the tools it is meant to test, so a failed
" install cannot quietly skip their tests.
function! Test_expected_search_tools_are_present()
  let mode = $VIM_PROJECT_TEST_TOOLS
  if mode ==# 'all'
    for program in ['rg', 'ag', 'fd', 'grep', 'find']
      call assert_true(executable(program), program.' is installed')
    endfor
  elseif mode ==# 'system'
    for program in ['rg', 'ag', 'fd']
      call assert_false(executable(program), program.' is not installed')
    endfor
    for program in ['grep', 'find']
      call assert_true(executable(program), program.' is installed')
    endfor
  endif
endfunction
