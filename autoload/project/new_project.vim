let s:origin_name = ''
let s:name = ''
let s:new_tasks = []
" Display row of each task, by name
let s:rows = {}

function! project#new_project#NewProject(name)
  call s:ParseName(a:name)
  if s:IsUrlName()
    call s:RunGitCloneUrl()
    return
  endif

  if !s:IsValidName()
    call project#Warn(s:name.' already exists')
    return
  endif

  let prompt = '['.s:GetCwd().'] create ['.s:GetName().'] by:'
  call project#list#Open({
        \'type': 'NEW_PROJECT',
        \'prompt': prompt,
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \})
endfunction

function! s:RunGitCloneUrl()
  let s:name = substitute(s:name, '?.*$', '', 'g')
  let s:origin_name = fnamemodify(s:name, ':t')
  let cmd = 'git clone '.s:name
  let task = { 'name': 'git', 'cmd': 'git clone' }
  call s:RunCmd(cmd, task)
endfunction

function! s:ParseName(name)
  let s:origin_name = a:name
  let args = split(a:name, ' *\("\|''\)')
  let s:name = expand(args[0])
endfunction

function! s:GetCwd()
  let new_project_base = project#config#Get('new_project_base')
  if empty(new_project_base) || !project#IsRelativePath(s:name)
    return fnamemodify(s:name, ':p:h')
  endif

  return expand(new_project_base)
endfunction

function! s:GetName()
  return fnamemodify(s:name, ':t')
endfunction

function! s:IsValidName()
  return !filereadable(s:name) && !isdirectory(s:name)
endfunction

function! s:IsUrlName()
  return match(s:name, '^https\?:') != -1 || match(s:name, '^git:') != -1
endfunction

function! s:Init(input)
  let s:new_tasks = project#config#Get('new_tasks')
  let columns = project#list#Tabulate(s:new_tasks, ['name', 'cmd', 'args'])

  let s:rows = {}
  for idx in range(len(s:new_tasks))
    let task = s:new_tasks[idx]
    let row = columns[idx].name.'  '.columns[idx].cmd
    if project#util#HasArgs(task)
      let row = row.'  '.columns[idx].args
    endif
    let s:rows[task.name] = row
  endfor

  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterTasks(copy(s:new_tasks), a:input)
  let display = map(copy(list), {_, task -> s:rows[task.name]})

  let state = project#list#State()
  let state.list = list
  call project#list#Show(display, a:input)
  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
endfunction

function! s:Open(task, open_cmd, input)
  let cmd = a:task.cmd
  if project#util#HasArgs(a:task)
    let args = input('['.s:GetCwd().'] '.a:task.cmd.' | '.a:task.args.': ')
    if !empty(args)
      let cmd = cmd.' '.args
    endif
  endif

  let cmd = cmd.' '.s:GetName()
  call s:RunCmd(cmd, a:task)
endfunction

function! s:RunCmd(cmd, task)
  let cwd = s:GetCwd()
  let OnExit = function('s:OnJobEnd', [a:task, a:cmd])
  if has('nvim')
    new
    call termopen(a:cmd, {
          \'on_exit': OnExit,
          \'cwd': cwd,
          \})
    startinsert
  else
    call term_start(a:cmd, {
          \'exit_cb': OnExit,
          \'cwd': cwd,
          \})
  endif
endfunction

function! s:OnJobEnd(task, cmd, job, status, ...)
  if empty(s:name) || a:status != 0
    return
  endif
  let error = project#AddProject(s:origin_name)
  if !empty(error)
    return
  endif

  let PostCmd = project#config#Get('new_tasks_post_cmd')
  let PostCmd_type = type(PostCmd)
  if PostCmd_type == type(function('tr'))
    let post_cmd = PostCmd(s:GetName(), a:task, a:cmd)
  elseif PostCmd_type == type('')
    let post_cmd = PostCmd
  endif
  if empty(post_cmd)
    return
  endif

  call project#RunShellCmd(post_cmd)

  if a:status != 0
    call project#Warn('Error on creating ['.s:name.']')
  endif
endfunction

function! s:FilterTasks(tasks, input)
  return project#util#FuzzyScore(a:tasks, a:input, ['name', 'cmd'], {'sort': 0})
endfunction
