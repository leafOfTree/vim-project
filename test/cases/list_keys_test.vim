" Tests for typing in a list (autoload/project/list.vim): the keys are fed
" before the list opens, then read one by one by its getchar() loop.
let s:list_buffer = 'vim_project_list'
let s:items = ['alpha', 'beta', 'gamma', 'delta']

function! s:Init(input)
  call s:Update(a:input)
endfunction

" Like a real list: filter, show, highlight the selected line
function! s:Update(input)
  let state = project#list#State()
  let state.list = filter(copy(s:items), {_, item -> stridx(item, a:input) != -1})
  call project#list#Show(state.list, a:input)
  call project#list#HighlightCurrentLine(len(state.list))
  call add(s:calls, ['update', a:input])
endfunction

function! s:Open(target, cmd, input)
  call add(s:calls, ['open', a:target, a:cmd, a:input])
endfunction

function! s:Close()
  call add(s:calls, ['close'])
endfunction

function! s:Spec(...)
  let spec = {
        \'type': 'KEYS_TEST',
        \'prompt': 'Test:',
        \'mappings': {'open_split': "\<C-s>", 'my_command': "\<C-g>"},
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \'Close': function('s:Close'),
        \}
  return extend(spec, get(a:000, 0, {}))
endfunction

" Type a:keys into a list opened with a:spec, return what it called
function! s:Type(keys, ...)
  let s:calls = []
  call feedkeys(a:keys, 't')
  call project#list#Open(call('s:Spec', a:000))
  return s:calls
endfunction

function! s:Inputs(calls)
  return map(filter(copy(a:calls), 'v:val[0] ==# "update"'), 'v:val[1]')
endfunction

function! s:Last(calls)
  return a:calls[-1]
endfunction

function! Test_list_keys_edit_the_input()
  let calls = s:Type("ab\<BS>c\<C-w>xy z\<C-u>q\<Esc>")
  " <BS> deletes a character, <C-w> a word, <C-u> everything
  call assert_equal(['', 'a', 'ab', 'a', 'ac', '', 'x', 'xy', 'xy ', 'xy z', '', 'q'], s:Inputs(calls))
  " <Esc> closes without opening
  call assert_equal(['close'], s:Last(calls))
  call assert_equal(-1, bufwinnr(s:list_buffer))
endfunction

function! Test_list_keys_move_the_selection()
  " The last item is selected first, at the bottom
  call assert_equal(['open', 'delta', 'open', ''], s:Last(s:Type("\<CR>")))
  call assert_equal(['open', 'beta', 'open', ''], s:Last(s:Type("\<C-k>\<C-k>\<CR>")))
  call assert_equal(['open', 'gamma', 'open', ''], s:Last(s:Type("\<Up>\<Up>\<Down>\<CR>")))
  call assert_equal(['open', 'alpha', 'open', ''], s:Last(s:Type("\<C-h>\<CR>")))
  call assert_equal(['open', 'delta', 'open', ''], s:Last(s:Type("\<C-h>\<C-l>\<CR>")))
  " Moving past either end stays on the first or last item
  call assert_equal(['open', 'alpha', 'open', ''], s:Last(s:Type(repeat("\<C-k>", 9)."\<CR>")))
  call assert_equal(['open', 'delta', 'open', ''], s:Last(s:Type(repeat("\<C-j>", 9)."\<CR>")))
endfunction

function! Test_list_keys_filter_then_open()
  call assert_equal(['open', 'gamma', 'open', 'ga'], s:Last(s:Type("ga\<CR>")))
  " A list specific key opens in another way
  call assert_equal(['open', 'beta', 'open_split', 'et'], s:Last(s:Type("et\<C-s>")))
endfunction

function! Test_list_keys_open_without_items_warns()
  messages clear
  let calls = s:Type("zzz\<CR>")
  call assert_equal(0, len(filter(copy(calls), 'v:val[0] ==# "open"')))
  call assert_match('No item selected', execute('messages'))
endfunction

function! Test_list_keys_run_list_handlers()
  " '' keeps the list open, the handler may change the input
  let Append = {state -> execute('let state.user_input .= "!"')}
  let calls = s:Type("a\<C-g>\<Esc>", {'handlers': {'my_command': {state -> [Append(state), ''][1]}}})
  call assert_equal(['', 'a', 'a!'], s:Inputs(calls))
  " 'close' closes it (no keys after it: they would stay queued)
  let calls = s:Type("\<C-g>", {'handlers': {'my_command': {state -> 'close'}}})
  call assert_equal([''], s:Inputs(calls))
  call assert_equal(['close'], s:Last(calls))
  " 'open' opens the selected item with the command
  let calls = s:Type("\<C-g>", {'handlers': {'my_command': {state -> 'open'}}})
  call assert_equal(['open', 'delta', 'my_command', ''], s:Last(calls))
endfunction

function! Test_list_keys_switch_to_list_keeps_window()
  let windows = winnr('$')
  call s:Type("\<C-o>")
  call assert_notequal(-1, bufwinnr(s:list_buffer))
  call assert_equal(s:list_buffer, bufname('%'))
  execute 'bwipeout!' bufnr(s:list_buffer)
  call assert_equal(windows, winnr('$'))
endfunction

function! Test_list_keys_restore_options()
  set laststatus=2 ruler
  call s:Type("ab\<Esc>")
  call assert_equal(2, &laststatus)
  call assert_equal(1, &ruler)
endfunction

" ---------------------------------------------------------------- project list

function! Test_project_list_filters_and_opens_by_typing()
  let base = Helper_TmpDir('project list')
  let projects = project#GetProjects()
  let added = []
  for name in ['alpha-proj', 'beta-proj']
    call mkdir(base.'/'.name)
    let project = {'name': name, 'path': base, 'fullpath': base.'/'.name, 'note': '', 'option': {}}
    call Helper_Call('autoload/project.vim', 'InitProjectConfig', [project])
    call add(projects, project)
    call add(added, project)
  endfor
  try
    " Characters in order, not a substring: 'btp' matches 'beta-proj'
    call feedkeys("btp\<CR>", 't')
    ProjectList
    call assert_equal('beta-proj', get(g:vim_project, 'name', ''))
  finally
    call project#QuitProject()
    call filter(projects, {_, p -> index(added, p) == -1})
    silent! %bwipeout!
  endtry
endfunction

" ---------------------------------------------------------------- highlight

" Typed characters must stand out, also where Constant looks like Normal
" (Neovim 0.10+ default colors)
function! Test_list_match_highlight_stands_out()
  silent! highlight clear VimProjectMatch
  call s:Type("\<Esc>")
  let match = synIDtrans(hlID('InputChar'))
  call assert_equal(hlID('VimProjectMatch'), match)
  call assert_equal('1', synIDattr(match, 'bold'))
  let normal = synIDtrans(hlID('Normal'))
  let differs = synIDattr(match, 'fg#', 'gui') !=? synIDattr(normal, 'fg#', 'gui')
        \ || synIDattr(match, 'fg', 'cterm') !=# synIDattr(normal, 'fg', 'cterm')
        \ || synIDattr(match, 'underline') ==# '1'
  call assert_true(differs, 'same color as Normal: '.synIDattr(match, 'fg#', 'gui'))
endfunction

function! Test_list_match_highlight_keeps_user_colors()
  highlight VimProjectMatch guifg=#123456 ctermfg=1 gui=italic cterm=italic
  try
    call s:Type("\<Esc>")
    call assert_equal('#123456', synIDattr(hlID('VimProjectMatch'), 'fg#', 'gui'))
  finally
    highlight clear VimProjectMatch
  endtry
endfunction
