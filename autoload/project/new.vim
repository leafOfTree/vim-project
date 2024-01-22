let s:name = ''

function! project#new#NewProject(name)
  let s:name = expand(a:name)
  if !s:IsValidName()
    call project#Warn(s:name.' already exists')
    return 
  endif

  let prompt = '['.s:GetCwd().'] create ['.s:GetName().'] by:' 

  call project#PrepareListBuffer(prompt, 'GIT_FILE_HISTORY')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:GetCwd()
  return fnamemodify(s:name, ':p:h')
endfunction

function! s:GetName()
  return fnamemodify(s:name, ':t')
endfunction

function! s:IsValidName()
  return !filereadable(s:name) && !isdirectory(s:name)
endfunction

function! s:Init(input)
  let s:new_tasks = project#GetVariable('new_tasks')
  let max_col_width = project#GetVariable('max_width') / 2 - 10
  call project#Tabulate(s:new_tasks, ['name', 'cmd', 'args'])
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterTasks(copy(s:new_tasks), a:input)
  let display = s:GetNewProjectTaskDisplay(list)
  call project#SetVariable('list', list)

  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
endfunction

function! s:Open(item, open_cmd, input)
  let cmd = a:item.cmd
  if s:WithArgs(a:item)
    let args = input('['.s:GetCwd().'] '.a:item.cmd.' | '.a:item.args.': ')
    if !empty(args)
      let cmd = cmd.' '.args
    endif
  endif

  let cmd = cmd.' '.s:GetName()
  if has('nvim')
    new
    call termopen(cmd, {
          \'on_exit': function('s:OnJobEnds'),
          \'cwd': s:GetCwd(),
          \})
  else
    call term_start(cmd, { 
          \'exit_cb': function('s:OnJobEnds'),
          \'cwd': s:GetCwd(),
          \})
  endif
endfunction

function! s:OnJobEnds(job, status, ...)
  if !empty(s:name) && a:status == 0
    let error = project#AddProject(s:name)
    if empty(error)
      let post_cmd = project#GetVariable('new_tasks_post_cmd')
      if !empty(post_cmd)
        call project#RunShellCmd(post_cmd)
      endif
    endif
  endif

  if a:status != 0
    call project#Warn('Error on creating ['.s:name.']')
  endif
endfunction

" function! s:OnTerminalLeave()
  " call timer_start(100, 's:OpenNewProject')
" endfunction
" 
" function! s:OpenNewProject(timer)
  " if !empty(s:name)
    " call project#AddProject(s:name)
  " endif
" endfunction

function! s:WithArgs(item)
  return has_key(a:item, 'args')
endfunction

function! s:GetNewProjectTaskDisplay(list)
  let display = []
  for item in a:list
    let row = item.__name.'  '.item.__cmd
    if s:WithArgs(item)
      let row = row.'  '.item.__args
    endif
    call add(display, row)
  endfor

  return display
endfunction

function! s:FilterTasks(tasks, input)
  let regexp_input = join(split(a:input, '\zs'), '.*')
  for item in a:tasks
    let item._match_type = ''
    let item._match_index = -1

    let match_index = match(item.name, regexp_input)
    if match_index != -1
      " Prefer exact match. If not, add 10 to match_index
      if len(a:input) > 1 && count(tolower(item.name), a:input) == 0
        let match_index = match_index + 10
      endif
      let item._match_type = 'name'
      let item._match_index = match_index
    endif

    if match_index == -1
      let match_index = match(item.cmd, regexp_input)
      if match_index != -1
        let item._match_type = 'cmd'
        let item._match_index = match_index
      endif
    endif
  endfor

  let result = filter(a:tasks, { _, val -> val._match_type != '' })
  return result
endfunction

