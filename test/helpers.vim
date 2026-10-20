" Shared helpers for test cases. Names start with "Helper_" so the runner's
" "Test_" discovery skips them.

" Return the <SNR> id of a sourced script whose path ends with a:suffix,
" e.g. 'autoload/project.vim' or 'autoload/project/git.vim'.
function! Helper_Sid(suffix)
  let suffix = substitute(a:suffix, '\\', '/', 'g')
  for info in s:ScriptInfo()
    let name = substitute(fnamemodify(info.name, ':p'), '\\', '/', 'g')
    if name[len(name) - len(suffix):] ==# suffix
      return info.sid
    endif
  endfor
  throw 'Script not loaded: '.a:suffix
endfunction

" List of {'sid': N, 'name': path} of sourced scripts
function! s:ScriptInfo()
  if exists('*getscriptinfo')
    return getscriptinfo()
  endif
  let infos = []
  for line in split(execute('scriptnames'), "\n")
    let m = matchlist(line, '^\s*\(\d\+\): \(.*\)$')
    if !empty(m)
      call add(infos, {'sid': str2nr(m[1]), 'name': expand(m[2])})
    endif
  endfor
  return infos
endfunction

" Call script-local function a:name defined in the script a:suffix.
function! Helper_Call(suffix, name, args)
  return call(Helper_Funcref(a:suffix, a:name), a:args)
endfunction

" Funcref to a script-local function, usable with sort(), map(), etc.
function! Helper_Funcref(suffix, name)
  return function(printf('<SNR>%d_%s', Helper_Sid(a:suffix), a:name))
endfunction

" Script-local variables (the s: dict) of the script a:suffix.
function! Helper_ScriptVars(suffix)
  " Set up by the runner for editors that can't read them by getscriptinfo()
  let Vars = 'Helper_ScriptVars_'.substitute(a:suffix, '\W', '_', 'g')
  if exists('*'.Vars)
    return call(Vars, [])
  endif
  let info = getscriptinfo({'sid': Helper_Sid(a:suffix)})
  if empty(info) || !has_key(info[0], 'variables')
    throw 'getscriptinfo() does not expose script variables in this editor'
  endif
  return info[0].variables
endfunction

" Read a script-local variable of the script a:suffix.
function! Helper_ScriptVar(suffix, name)
  return Helper_ScriptVars(a:suffix)[a:name]
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
