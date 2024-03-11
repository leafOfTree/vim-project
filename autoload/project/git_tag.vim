let s:name = ''
let s:splitter = ' '
let s:splitter_regexp = '^\S\+\zs'
let s:item_splitter = '----------------------------------------------'
let s:item_new_tag = '+ New Tag'

function! project#git_tag#Show()
  let prompt = 'Search tags:' 

  call project#PrepareListBuffer(prompt, 'GIT_TAG')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let cmd = 'git tag -n'
  let tags = reverse(project#RunShellCmd(cmd))
  let s:list = s:GetTabulatedList(tags)
  call add(s:list, s:CreateItem(s:item_splitter))
  call add(s:list, s:CreateItem(s:item_new_tag))
  call s:Update(a:input)
endfunction

function! s:FindCurrentTag()
  let cmd = 'git tag --points-at HEAD'
  let current = project#RunShellCmd(cmd)
  if v:shell_error
    return ''
  endif
  return current
endfunction

function! s:Update(input)
  let list = s:FilterTags(s:list, a:input)
  call project#SetVariable('list', list)
  let display = s:GetTagsDisplay(list, a:input)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
  call s:HighlightSpecialItem()
endfunction

function! s:Open(tag, open_cmd, input)
  if a:tag.name == s:item_new_tag
    call s:CreateNewTag()
    return
  endif

  let cmd = 'git checkout '.a:tag.name

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
  return { 'name': a:text, '__name': a:text, 'message': '' }
endfunction

function! s:FilterTags(list, input)
  let list = copy(a:list)
  if empty(a:input)
    return list
  endif
  let pattern = s:GetRegexpFilter(a:input)
  let list = filter(list, { idx, val ->
        \s:Match(val.name, pattern) || s:Match(val.message, pattern)
        \})
  return list
endfunction

function! s:GetRegexpFilter(input)
  return join(split(a:input, ' '), '.*')
endfunction

function! s:Match(string, pattern)
  return match(a:string, a:pattern) != -1
endfunction

function! s:GetTabulatedList(tags)
  let list = []
  for tag in a:tags
    let [name, message] = split(tag, s:splitter_regexp, 1)
    let message = substitute(message, '^\s*', '', 'g')
    call insert(list, { 'name': name, 'message': message })
  endfor

  call project#Tabulate(list, ['name'])
  return list
endfunction

function! s:GetTagsDisplay(list, input)
  let display = map(copy(a:list), function('s:GetTagsDisplayRow'))
  return display
endfunction

function! s:GetTagsDisplayRow(idx, value)
  return a:value.__name.' '.a:value.message
endfunction

