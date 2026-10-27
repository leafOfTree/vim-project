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
  let s:refs = s:GetRefs()
  let s:list = s:LoadBranches()
  call s:Update(a:input)
  call s:StartFetch()
endfunction

function! s:LoadBranches()
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
  return s:GetTabulatedList(branches)
endfunction

" ---------------------------------------------------------------- fetch

" Remote branches are only as new as the last fetch: fetch in the background
" each time the list opens, then show them again if it is still open. git
" cannot ask for credentials without a terminal, so it fails instead
let s:fetch_job = v:null
let s:refs = []

function! s:StartFetch()
  if !project#config#Get('git_branch_fetch') || s:fetch_job isnot v:null
        \|| !(exists('*job_start') || exists('*jobstart'))
        \|| empty(project#RunShellCmd('git remote', 0))
    return
  endif

  let ctx = {'lines': []}
  let cmd = [&shell, &shellcmdflag, 'git fetch --all --prune --quiet']
  let env = {'GIT_TERMINAL_PROMPT': '0'}
  if exists('*job_start')
    let s:fetch_job = job_start(cmd, {
          \'cwd': $vim_project,
          \'env': env,
          \'in_io': 'null',
          \'out_cb': {_, line -> add(ctx.lines, line)},
          \'err_cb': {_, line -> add(ctx.lines, line)},
          \'exit_cb': function('s:OnVimFetchExit', [ctx]),
          \})
  else
    let s:fetch_job = jobstart(cmd, {
          \'cwd': $vim_project,
          \'env': env,
          \'stdin': 'null',
          \'stdout_buffered': v:true,
          \'stderr_buffered': v:true,
          \'on_stdout': {_, data, __ -> extend(ctx.lines, data)},
          \'on_stderr': {_, data, __ -> extend(ctx.lines, data)},
          \'on_exit': {_, status, __ -> s:OnFetched(status, ctx)},
          \})
  endif
endfunction

" exit_cb may run before the output was read
function! s:OnVimFetchExit(ctx, job, status)
  call timer_start(10, {-> s:OnFetched(a:status, a:ctx)})
endfunction

function! s:OnFetched(status, ctx)
  let s:fetch_job = v:null
  if !project#list#IsOpen('GIT_BRANCH')
    return
  endif
  if a:status != 0
    let lines = filter(copy(a:ctx.lines), '!empty(v:val)')
    call project#list#SetInfoOnClose('git fetch failed: '.get(lines, 0, 'exit '.a:status))
    return
  endif

  " Redraw only when a branch moved, not to flash the list for nothing
  let refs = s:GetRefs()
  if refs == s:refs
    return
  endif
  let list = s:LoadBranches()
  " Two items are New Branch and the splitter: keep the list on an error
  if len(list) <= 2
    return
  endif
  let s:refs = refs
  let s:list = list
  call s:Update(project#list#State().user_input)
  call project#list#RedrawInputLine()
endfunction

" Branches and the commits they point to, to tell whether a fetch changed any
function! s:GetRefs()
  let format = shellescape('%(refname) %(objectname) %(upstream)')
  let cmd = 'git for-each-ref --format='.format.' refs/heads refs/remotes'
  return project#RunShellCmd(cmd, 0)
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
