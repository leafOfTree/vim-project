let s:splitter = ' '
let s:splitter_regexp = '^\S\+\zs'
let s:item_splitter = '----------------------------------------------'
let s:item_new_tag = '+ New Tag'
let s:list = []

function! project#git_tag#Show()
  call project#list#Open({
        \'type': 'GIT_TAG',
        \'prompt': 'Search tags:',
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \})
endfunction

function! s:Init(input)
  let cmd = 'git tag -n'
  let tags = reverse(project#RunShellCmd(cmd))
  let s:list = s:GetTabulatedList(tags)
  call add(s:list, s:CreateItem(s:item_splitter))
  call add(s:list, s:CreateItem(s:item_new_tag))
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterTags(s:list, a:input)
  let state = project#list#State()
  let state.list = list
  let display = s:GetTagsDisplay(list, a:input)
  call project#list#Show(display, a:input)
  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
  call s:HighlightSpecialItem()
endfunction

function! s:Open(tag, open_cmd, input)
  if a:tag.name == s:item_new_tag
    call s:CreateNewTag()
    return
  endif

  let cmd = 'git checkout '.shellescape(a:tag.name)

  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif

  call project#Info('Switched to: '.a:tag.name)
endfunction

function! s:CreateNewTag()
  let name = input('git tag ', '')
  if empty(name)
    return
  endif

  let cmd = 'git tag '.name
  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif
  redraw
  call project#Info('Created new tag by: git tag '.name)
endfunction

function! s:HighlightSpecialItem()
  call matchadd('Keyword', '\* \S*')
endfunction

function! s:CreateItem(text)
  return { 'name': a:text, 'message': '', 'row': a:text.' ' }
endfunction

function! s:FilterTags(list, input)
  let list = copy(a:list)
  if empty(a:input)
    return list
  endif
  let pattern = project#util#GetRegexpFilter(a:input)
  let list = filter(list, { idx, val ->
        \project#util#Match(val.name, pattern) || project#util#Match(val.message, pattern)
        \})
  return list
endfunction

function! s:GetTabulatedList(tags)
  let list = []
  for tag in a:tags
    let [name, message] = split(tag, s:splitter_regexp, 1)
    let message = substitute(message, '^\s*', '', 'g')
    call insert(list, { 'name': name, 'message': message })
  endfor

  let columns = project#list#Tabulate(list, ['name'])
  for idx in range(len(list))
    let list[idx].row = columns[idx].name.' '.list[idx].message
  endfor
  return list
endfunction

function! s:GetTagsDisplay(list, input)
  return map(copy(a:list), {_, val -> val.row})
endfunction
