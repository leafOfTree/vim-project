" Headless test runner for vim-project.
"
" Loads the plugin from this repository with an isolated config home, sources
" every test/cases/*.vim file, then runs each global function whose name
" starts with "Test_". Failures are collected from v:errors.
"
" Results are written to $VIM_PROJECT_TEST_OUTPUT (or echoed when unset) and
" the editor exits with code 1 when any test fails. Works with both
"   nvim --headless -u NONE -i NONE -n -S test/runner.vim
"   vim -N -u NONE -i NONE -n -es -S test/runner.vim
set nocompatible
set encoding=utf-8
set nomore
set noswapfile
set shortmess+=F

let s:test_dir = expand('<sfile>:p:h')
let s:root = fnamemodify(s:test_dir, ':h')

" Everything the plugin writes goes under this temporary directory.
let g:vim_project_test_tmp = fnamemodify(tempname(), ':p:h').'/vim-project-test-'.getpid()
call mkdir(g:vim_project_test_tmp.'/config', 'p')
call mkdir(g:vim_project_test_tmp.'/base', 'p')

" -u NONE leaves the default highlight groups (Comment, Function, ...)
" undefined in Vim; the list buffer derives its colors from them.
syntax enable

" Capture the options the list window must restore.
set laststatus=2
set ruler

let g:vim_project_config = {
      \'config_home': g:vim_project_test_tmp.'/config',
      \'project_base': [g:vim_project_test_tmp.'/base'],
      \'auto_detect': 'no',
      \'debug': 0,
      \}

let &runtimepath = s:root.','.&runtimepath
runtime plugin/project.vim

" Load the modules under test so their script-local functions exist.
runtime autoload/project/find_in_files.vim
runtime autoload/project/list_projects.vim
runtime autoload/project/git.vim

execute 'source '.fnameescape(s:test_dir.'/helpers.vim')
for s:file in sort(glob(s:test_dir.'/cases/*.vim', 0, 1))
  execute 'source '.fnameescape(s:file)
endfor

function! s:ListTests()
  let names = []
  for line in split(execute('function /^Test_'), "\n")
    let name = matchstr(line, '^function \zsTest_\w\+\ze(')
    if !empty(name)
      call add(names, name)
    endif
  endfor
  return sort(names)
endfunction

function! s:Run()
  let lines = []
  let passed = 0
  let failed = 0

  for name in s:ListTests()
    let v:errors = []
    try
      call call(name, [])
    catch
      call add(v:errors, 'Exception: '.v:exception.' at '.v:throwpoint)
    endtry

    if empty(v:errors)
      let passed += 1
      call add(lines, 'ok    '.name)
    else
      let failed += 1
      call add(lines, 'FAIL  '.name)
      for error in v:errors
        call add(lines, '        '.error)
      endfor
    endif
  endfor

  call add(lines, '')
  call add(lines, printf('%s: %d passed, %d failed, %d total',
        \ has('nvim') ? 'nvim' : 'vim', passed, failed, passed + failed))
  return [failed, lines]
endfunction

let [s:failed, s:lines] = s:Run()

if !empty($VIM_PROJECT_TEST_OUTPUT)
  call writefile(s:lines, $VIM_PROJECT_TEST_OUTPUT)
else
  for s:line in s:lines
    echo s:line
  endfor
endif

call delete(g:vim_project_test_tmp, 'rf')

if s:failed > 0
  cquit!
endif
qall!
