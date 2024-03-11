let s:name = ''
let s:splitter = ' ||| '
let s:item_splitter = '----------------------------------------------'
let s:item_new_branch = 'New Branch'

function! project#git_branch#Show()
  let prompt = 'Switch to a branch:' 

  call project#PrepareListBuffer(prompt, 'GIT_BRANCH')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let format = join(['%(HEAD)', '%(refname:short)', '%(upstream:short)', 
        \'%(contents:subject)', '%(authorname)',  '%(committerdate:relative)'], s:splitter)
  let cmd = "git branch -a --format='".format."'"
  let branches = project#RunShellCmd(cmd)
  let current = filter(copy(branches), 'v:val[0] == "*"')
  call filter(branches, 'v:val[0] != "*"')
  call insert(branches, current[0])
  call insert(branches, s:CreateItem(' ', s:item_splitter))
  call insert(branches, s:CreateItem('+', s:item_new_branch))
  let s:list = s:GetTabulatedList(branches)
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterBranches(s:list, a:input)
  call project#SetVariable('list', list)
  let display = s:GetBranchesDisplay(list, a:input)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
  call s:HighlightSpecialItem()
endfunction

function! s:Open(branch, open_cmd, input)
  if a:branch.head == '*' || a:branch.name == s:item_splitter
    return
  elseif a:branch.head == '+'
    call s:CreateNewBranch()
    return
  endif

  let name = split(a:branch.name, '/')[-1]
  let is_head = s:IsHead(name)
  let name_exist = s:CheckNameExist(name)

  if is_head 
    let cmd = 'git checkout '.a:branch.name
  elseif name_exist
    let cmd = 'git switch '.name
  else
    let cmd = 'git switch -c '.name.' '.a:branch.name
  endif

  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif
  if !is_head
    let set_upstream_cmd = 'git branch --set-upstream-to '.a:branch.name
    call project#RunShellCmd(set_upstream_cmd)
    if v:shell_error
      return
    endif
  endif

  call project#Info('Switched to: '.a:branch.name)
endfunction

function! s:CreateNewBranch()
  let name = input('New branch name: ', '')
  if empty(name)
    return
  endif

  let cmd = 'git switch -c '.name
  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif
  redraw
  call project#Info('Switched to new branch: '.name)
endfunction

function! s:IsHead(name)
  return a:name == 'HEAD'
endfunction

function! s:CheckNameExist(name)
  let check_exist_cmd = 'git show-ref --verify --quiet refs/heads/'.a:name
  call project#RunShellCmd(check_exist_cmd)
  return !v:shell_error
endfunction

function! s:HighlightSpecialItem()
  call matchadd('Keyword', '\* \S*')
endfunction

function! s:CreateItem(head, text)
  return a:head.s:splitter.a:text.s:splitter.s:splitter.s:splitter.s:splitter
endfunction

function! s:FilterBranches(list, input)
  let list = copy(a:list)
  if empty(a:input)
    return list
  endif
  let pattern = s:GetRegexpFilter(a:input)
  let list = filter(list, { idx, val ->
        \s:Match(val.name, pattern)})
  return list
endfunction

function! s:GetRegexpFilter(input)
  return join(split(a:input, ' '), '.*')
endfunction

function! s:Match(string, pattern)
  return match(a:string, a:pattern) != -1
endfunction

function! s:GetTabulatedList(branches)
  let list = []
  for branch in a:branches
    let [head, name, upstream, subject, authorname, date] = split(branch, s:splitter, 1)
    let date = project#ShortenDate(date)
    let show_name = empty(upstream) ? name : name.' -> '.upstream
    call insert(list, {
          \'head': head, 'name': name, 'show_name': show_name, 'date': date,
          \'upstream': upstream, 'subject': subject, 'authorname': authorname,
          \})
  endfor

  call project#Tabulate(list, ['show_name'])
  return list
endfunction

function! s:GetBranchesDisplay(list, input)
  let display = map(copy(a:list), function('s:GetBranchesDisplayRow'))
  return display
endfunction

function! s:GetBranchesDisplayRow(idx, value)
  let author_info = empty(a:value.date) ? '' : ' ('.a:value.authorname.', '.a:value.date.')'
  return a:value.head.' '.a:value.__show_name.' '.a:value.subject.author_info
endfunction

