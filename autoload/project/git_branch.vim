let s:splitter = ' ||| '
let s:item_splitter = '----------------------------------------------'
let s:item_new_branch = 'New Branch'
let s:list = []

function! project#git_branch#Show()
  call project#list#Open({
        \'type': 'GIT_BRANCH',
        \'prompt': 'Switch to a branch:',
        \'mappings': project#config#Get('list_mappings_git_branch'),
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \'handlers': {
        \  'merge_branch': function('s:MergeBranch'),
        \},
        \'Highlight': function('s:Highlight'),
        \})
endfunction

function! s:Highlight(state)
  let a:state.first_column_pattern = '^\( \|\*\) '.a:state.column_pattern
  highlight link FirstColumn Normal
  highlight link SecondColumn Comment
endfunction

function! s:Init(input)
  let format = join(['%(HEAD)', '%(refname:short)', '%(upstream:short)',
        \'%(contents:subject)', '%(authorname)',  '%(committerdate:relative)'], s:splitter)
  let cmd = 'git branch -a --format='.shellescape(format)
  let branches = project#RunShellCmd(cmd)
  let current = filter(copy(branches), 'v:val[0] == "*"')
  call filter(branches, 'v:val[0] != "*"')
  if !empty(current)
    call insert(branches, current[0])
  endif
  call insert(branches, s:CreateItem(' ', s:item_splitter))
  call insert(branches, s:CreateItem('+', s:item_new_branch))
  let s:list = s:GetTabulatedList(branches)
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterBranches(s:list, a:input)
  let state = project#list#State()
  let state.list = list
  let display = s:GetBranchesDisplay(list, a:input)
  call project#list#Show(display, a:input)
  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
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
    let cmd = 'git checkout '.shellescape(a:branch.name)
  elseif name_exist
    let cmd = 'git switch '.shellescape(name)
  else
    let cmd = 'git switch -c '.shellescape(name).' '.shellescape(a:branch.name)
  endif

  call project#RunShellCmd(cmd)
  if v:shell_error
    return
  endif
  if !is_head
    let set_upstream_cmd = 'git branch --set-upstream-to '.shellescape(a:branch.name)
    call project#RunShellCmd(set_upstream_cmd)
    if v:shell_error
      return
    endif
  endif
  edit
  call project#Info('Switched to: '.a:branch.name)
endfunction

" Merge the selected branch into the current one once confirmed, then close
" the list. Nothing to merge on the current branch or the other items
function! s:MergeBranch(state)
  let target = project#list#GetTarget()
  if empty(target) || target.head != ' ' || target.name == s:item_splitter
    return ''
  endif

  let show_current_cmd = 'git branch --show-current'
  let current = get(project#RunShellCmd(show_current_cmd), 0, 'HEAD')
  let name = target.name

  " Like rollback, ask first: the key is easy to press by habit. In place of
  " the input line, so the messages after it don't ask to press Enter
  redraw
  echo 'Merge '.name.' into '.current.'? (y/n) '
  let answer = nr2char(getchar())
  redraw
  if answer !=# 'y'
    return ''
  endif

  let cmd = 'git merge '.shellescape(name)

  let output = project#RunShellCmd(cmd, 0)
  if v:shell_error
    " Once the list is closed
    call timer_start(0, {-> project#git_merge#ShowConflicts()
          \|| project#WarnCommandOutput(cmd, output)})
    return 'close'
  endif
  let a:state.offset = 0

  call project#list#SetInfoOnClose('Merged '.name.' into '.current)
  return 'close'
endfunction

function! s:GetSafeBranchName(raw_name)
  let name = substitute(a:raw_name, '[^a-zA-Z0-9_-]', '-', 'g')

  " Remove leading hyphens
  let name = substitute(name, '^-\+', '', '')

  " Remove trailing hyphens
  let name = substitute(name, '-\+$', '', '')

  " Replace multiple consecutive hyphens with a single hyphen
  let name = substitute(name, '-\+', '-', 'g')
  return name
endfunction

function! s:CreateNewBranch()
  let raw_name = input('New branch name: ', '')
  if empty(raw_name)
    return
  endif

  let name = s:GetSafeBranchName(raw_name)

  let cmd = 'git switch -c '.shellescape(name)
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
  let check_exist_cmd = 'git show-ref --verify --quiet '.shellescape('refs/heads/'.a:name)
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
  let pattern = project#util#GetRegexpFilter(a:input)
  let list = filter(list, { idx, val ->
        \project#util#Match(val.name, pattern)})
  return list
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

  let columns = project#list#Tabulate(list, ['show_name'])
  for idx in range(len(list))
    let item = list[idx]
    let author_info = empty(item.date) ? '' : ' ('.item.authorname.', '.item.date.')'
    let item.row = item.head.' '.columns[idx].show_name.' '.item.subject.author_info
  endfor
  return list
endfunction

function! s:GetBranchesDisplay(list, input)
  return map(copy(a:list), {_, val -> val.row})
endfunction
