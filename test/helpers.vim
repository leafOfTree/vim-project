" Shared helpers for test cases. Names start with "Helper_" so the runner's
" "Test_" discovery skips them.

" Return the <SNR> id of a sourced script whose path ends with a:suffix,
" e.g. 'autoload/project.vim' or 'autoload/project/git.vim'.
function! Helper_Sid(suffix)
  let suffix = substitute(a:suffix, '\\', '/', 'g')
  for info in getscriptinfo()
    let name = substitute(fnamemodify(info.name, ':p'), '\\', '/', 'g')
    if name[len(name) - len(suffix):] ==# suffix
      return info.sid
    endif
  endfor
  throw 'Script not loaded: '.a:suffix
endfunction

" Call script-local function a:name defined in the script a:suffix.
function! Helper_Call(suffix, name, args)
  return call(Helper_Funcref(a:suffix, a:name), a:args)
endfunction

" Funcref to a script-local function, usable with sort(), map(), etc.
function! Helper_Funcref(suffix, name)
  return function(printf('<SNR>%d_%s', Helper_Sid(a:suffix), a:name))
endfunction

" Read a script-local variable of the script a:suffix.
function! Helper_ScriptVar(suffix, name)
  let info = getscriptinfo({'sid': Helper_Sid(a:suffix)})
  if empty(info) || !has_key(info[0], 'variables')
    throw 'getscriptinfo() does not expose script variables in this editor'
  endif
  return info[0].variables[a:name]
endfunction

" Create (and return) a fresh temporary directory under the test root.
function! Helper_TmpDir(name)
  let dir = g:vim_project_test_tmp.'/'.a:name
  call delete(dir, 'rf')
  call mkdir(dir, 'p')
  return dir
endfunction

" Assert that a:needle occurs in a:haystack.
function! Helper_AssertContains(haystack, needle, ...)
  let msg = a:0 ? a:1 : ''
  call assert_true(stridx(a:haystack, a:needle) != -1,
        \ printf('%sexpected "%s" to contain "%s"', empty(msg) ? '' : msg.': ', a:haystack, a:needle))
endfunction

" Assert that a:needle does not occur in a:haystack.
function! Helper_AssertNotContains(haystack, needle, ...)
  let msg = a:0 ? a:1 : ''
  call assert_true(stridx(a:haystack, a:needle) == -1,
        \ printf('%sexpected "%s" not to contain "%s"', empty(msg) ? '' : msg.': ', a:haystack, a:needle))
endfunction
