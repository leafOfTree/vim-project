let s:output_rows = 20
let s:terminal_bufnr = -1
let s:run_tasks_timer = 0
" Runtime state of started tasks, by task name. Keys: bufnr (job id on nvim),
" started, started_rel, duration, exit_code, finished. The config task dicts
" are never changed
let s:task_state = {}
" Display column of each task, by name
let s:rows = {}

function! project#run_tasks#Run()
  call project#list#Open({
        \'type': 'RUN_TASKS',
        \'prompt': 'Run a task:',
        \'mappings': project#config#Get('list_mappings_run_tasks'),
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \'Close': function('s:StopTimer'),
        \'handlers': {
        \  'run_task': function('s:RunTaskHandler'),
        \  'stop_task': function('s:StopTaskHandler'),
        \},
        \'ItemStep': function('s:ItemStep'),
        \'Highlight': function('s:Highlight'),
        \'save_history': 1,
        \})
endfunction

" Tasks of the config without the ones that have neither name nor cmd
function! s:GetTasks()
  let tasks = copy(project#config#Get('tasks'))
  return filter(tasks, {idx, task -> !s:HasEmptyName(task) || !s:HasEmptyCmd(task)})
endfunction

function! s:Init(input)
  let tasks = s:GetTasks()
  let max_col_width = project#list#State().max_width - 10
  let columns = project#list#Tabulate(tasks, ['name'], 0, max_col_width)

  let s:rows = {}
  for idx in range(len(tasks))
    let s:rows[tasks[idx].name] = columns[idx].name
  endfor

  call s:Update(a:input)
endfunction

function! s:Update(input)
  call s:StopTimer()
  call s:RunTasksBufferUpdate(a:input)
  call s:StartTimer(a:input)
endfunction

function! s:Highlight(state)
  let a:state.first_column_pattern = '^'.a:state.column_pattern
  highlight link FirstColumn Keyword
  highlight link SecondColumn Comment
  call project#list#DefineDistinctHighlight('VimProjectRunning',
        \['WarningMsg', 'Special', 'Constant', 'Function'])
  highlight link Status VimProjectRunning

  " Linking InfoRow to Normal does not work when overriding other syntax
  if has('nvim') || !exists('*hlget')
    highlight link InfoRow Normal
  else
    let normal_hl = hlget('Normal')
    let normal_hl[0].name = 'InfoRow'
    call hlset(normal_hl)
  endif
  call s:HighlightRunTasksCmdOutput()
endfunction

" Move by task: skip the status and output rows of a task
function! s:ItemStep(direction)
  let current_line = project#list#GetCurrentLineNumber()
  call cursor(current_line, 1)
  if a:direction < 0
    let prev_task_line = search('^\w', 'bnW')
    return current_line - prev_task_line
  endif

  let next_task_line = search('^\w', 'nW')
  return next_task_line > current_line ? next_task_line - current_line : 0
endfunction

function! s:StartTimer(input)
  let s:run_tasks_timer = timer_start(500, function('s:RunTasksBufferUpdateTimer', [a:input]),
        \{'repeat': -1})
endfunction

function! s:StopTimer()
  call timer_stop(s:run_tasks_timer)
endfunction

function! s:RunTasksBufferUpdateTimer(input, id)
  call s:RunTasksBufferUpdate(a:input)
endfunction

function! s:GetTaskState(task)
  if !has_key(s:task_state, a:task.name)
    let s:task_state[a:task.name] = {}
  endif
  return s:task_state[a:task.name]
endfunction

function! s:HasTaskBufnr(task)
  return has_key(s:GetTaskState(a:task), 'bufnr')
endfunction

function! s:GetTaskBufnr(task)
  return s:GetTaskState(a:task).bufnr
endfunction

function! s:GetTaskStatusLine(task, status)
  let task_state = s:GetTaskState(a:task)
  if a:status == 'finished'
    let error = has_key(task_state, 'exit_code') && task_state.exit_code
    if error
      let icon = '❌ '.task_state.exit_code
    else
      let icon = '✅ '
    endif
  else
    let icon = '🏃' " 🔄
    let duration_full = split(reltimestr(reltime(task_state.started_rel)))[0]
    let task_state.duration = substitute(duration_full, '\..*', '', 'g')
  endif


  let width = &columns
  let left = '  ['.a:status.'] '.icon
  if has_key(task_state, 'duration')
    let right = task_state.duration.'s'
  else
    let right = ''
  endif
  if a:status == 'finished'
    if has_key(task_state, 'finished')
      let right = 'At '.task_state.finished.', '.right
    endif
  endif
  let padding_number = width - strwidth(left) - strwidth(right) - 2
  let padding = ''
  for i in range(padding_number)
    let padding .= ' '
  endfor
  return left.padding.right
endfunction

function! s:GetRunTasksDisplay(tasks)
  let display = []
  let list = []

  for task in a:tasks
    let task_row = s:rows[task.name]
    let task_row .= '  '.task.cmd
    if has_key(task, 'cd')
      let task_row .= '  (cd '.task.cd.')'
    endif
    call add(display, task_row)
    call add(list, task)

    if s:HasTaskBufnr(task) && s:GetTaskBufnr(task) > 0
      let status = s:GetTaskStatus(task)
      if status == ''
        continue
      endif

      " Add task status
      let output = s:GetTaskStatusLine(task, status)
      let item = {'name': task.name, 'cmd': task.cmd, 'output': output}
      call add(display, output)
      call add(list, item)

      " Add task output
      if has('nvim')
        call s:AddTaskOutputFromNvim(task, display, list)
      else
        if s:HasFilter(task)
          call s:AddTaskOutputWithFilter(task, display, list)
        else
          call s:AddTaskOutputFromVim(task, display, list)
        endif
      endif
    endif
  endfor
  return [display, list]
endfunction

function! s:AddTaskOutput(output, task, display, list)
  let item = {'name': a:task.name, 'cmd': a:task.cmd, 'output': a:output}
  call add(a:display, a:output)
  call add(a:list, item)
endfunction

function! s:AddTaskOutputFromNvim(task, display, list)
  let bufnr = s:GetNvimTaskBufnr(a:task)
  let lines = getbufline(bufnr, 1, '$')
  " Remove trailing space
  let lines = split(trim(join(lines, "\n")), "\n")
  let rows = len(lines)
  if rows <= s:output_rows
    for index in range(0, s:output_rows, 1)
      if index >= rows
        let output = '  '
      else
        let output = '  '.lines[index]
      endif
      call s:AddTaskOutput(output, a:task, a:display, a:list)
    endfor
  else
    for index in range(rows - s:output_rows, rows, 1)
      if index == rows
        let output = '  '
      else
        let output = '  '.lines[index]
      endif
      call s:AddTaskOutput(output, a:task, a:display, a:list)
    endfor
  endif
endfunction

function! s:AddTaskOutputFromVim(task, display, list)
  let bufnr = s:GetTaskBufnr(a:task)
  let rows = term_getcursor(bufnr)[0]
  for index in range(1, s:output_rows + 1, 1)
    if index > rows
      let output = '  '
    else
      let line = term_getline(bufnr, index)
      let output = '  '.line
    endif
    call s:AddTaskOutput(output, a:task, a:display, a:list)
  endfor
endfunction

function! s:AddTaskOutputWithFilter(task, display, list)
  let bufnr = s:GetTaskBufnr(a:task)
  let [rows, cols] = term_getsize(bufnr)
  let output_count = 0
  let output_list_backward = []
  for index in range(rows, 1, -1)
    if output_count > s:output_rows - 2
      break
    endif

    let line = term_getline(bufnr, index)
    if s:HasContent(line) && s:MatchUserDefinedPattern(line, a:task.show, a:task.hide)
      let output_count += 1
      call add(output_list_backward, '  '.line)
    endif
  endfor

  let output_list = reverse(output_list_backward)
  if output_count < s:output_rows
    for index in range(output_count, s:output_rows - 1, 1)
      call add(output_list, '  ')
    endfor
  endif

  for output in output_list
    call add(a:display, output)
    let item = {'name': a:task.name, 'cmd': a:task.cmd, 'output': output}
    call add(a:list, item)
  endfor
endfunction

function! s:HasContent(line)
  return match(a:line, '^\s*$') == -1
endfunction

function! s:MatchUserDefinedPattern(line, show, hide)
  let match = 1
  if !empty(a:show)
    let match = match && s:MatchAny(a:line, a:show)
  endif

  if !empty(a:hide)
    let match = match && !s:MatchAny(a:line, a:hide)
  endif

  return match

endfunction

function! s:MatchAny(str, pats)
  for pat in a:pats
    if match(a:str, pat) != -1
      return 1
    endif
  endfor

  return 0
endfunction

function! s:RunTasksBufferUpdate(input)
  " The timer may fire after the list has closed
  if !project#list#IsCurrentListBuffer()
    return
  endif

  let tasks = s:FilterRunTasks(s:GetTasks(), a:input)
  let [display, list] = s:GetRunTasksDisplay(tasks)
  let state = project#list#State()
  let state.list = list
  call project#list#Show(display, a:input)

  " Move to near task row
  if state.offset == 0 && getline('.') !~ '^\w'
    call project#list#UpdateOffsetByIndex(search('^\w', 'bnW') - 1)
  endif

  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
  call s:HighlightRunTasksCmdOutput()

  let state.user_input = a:input
  call project#list#RedrawInputLine()
endfunction

function! s:HighlightRunTasksCmdOutput()
  match InfoRow /^\s\{2,}.*/
  2match Status '\[running.*\]'
  3match Special '\[finished.*\]'
  call matchadd('Comment', 'At.*s$')
  call matchadd('Comment', '   \d\+s$')
endfunction

" <cr> on a task: run it and keep the list open. A task without cmd opens a
" terminal after the list has closed
function! s:RunTaskHandler(state)
  let task = project#list#GetTarget()
  if empty(task)
    call project#Warn('No item selected')
    return 'close'
  endif

  if s:HasEmptyCmd(task)
    return 'open'
  endif

  let keep_window = s:Open(task, 'run_task', a:state.user_input)
  return keep_window ? '' : 'close'
endfunction

function! s:StopTaskHandler(state)
  let task = project#list#GetTarget()
  if empty(task)
    return
  endif

  let index = project#list#GetCurrentIndex()
  call s:StopTask(task)
  call s:RunTasksBufferUpdate(a:state.user_input)
  call project#list#UpdateOffsetByIndex(index)
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:Open(task, open_cmd, input)
  call s:StopTimer()
  if a:open_cmd == 'open_task_terminal'
    return s:OpenTaskTerminal(a:task)
  endif

  " Open vim terminal if the task has empty cmd
  if s:HasEmptyCmd(a:task)
    call s:OpenTerminal()
    return 0
  endif

  let cmd = a:task.cmd
  if project#util#HasArgs(a:task)
    let args = input(
          \'[Run task: '.a:task.name.'] '.a:task.cmd.' | '.a:task.args.': ')
    if !empty(args)
      let cmd = cmd.' '.args
    endif
  endif

  return s:RunTask(a:task, cmd)
endfunction

function! s:OpenTerminal()
  if bufexists(s:terminal_bufnr)
    new
    execute 'buffer '.s:terminal_bufnr
    if has('nvim')
      startinsert
    else
      normal! i
    endif
    return
  endif

  let has_project = !empty($vim_project)
  if has('nvim')
    new
    if has_project
      cd $vim_project
    endif
    terminal
    startinsert
  else
    terminal ++kill=kill
    if has_project
      call term_sendkeys(bufnr('%'), "cd $vim_project\<CR>")
    endif
    call term_sendkeys(bufnr('%'), "clear\<CR>")
  endif

  let s:terminal_bufnr = bufnr()
endfunction

function! project#run_tasks#WipeoutTerminalBuffer()
  if bufexists(s:terminal_bufnr)
    execute 'silent bwipeout! '.s:terminal_bufnr
    let s:terminal_bufnr = -1
  endif
endfunction

function! s:HasEmptyCmd(task)
  return !has_key(a:task, 'cmd') || a:task.cmd == ''
endfunction

function! s:HasEmptyName(task)
  return !has_key(a:task, 'name') || a:task.name == ''
endfunction

function! s:GetNvimTaskBufnr(task)
  if !s:HasTaskBufnr(a:task)
    return 0
  endif
  let job_id = s:GetTaskBufnr(a:task)
  for buffer in getbufinfo({'buflisted': 1})
    let variables = buffer.variables
    if has_key(variables, 'terminal_job_id') && variables.terminal_job_id == job_id
      return buffer.bufnr
    endif
  endfor
  return 0
endfunction

function! s:OpenTaskTerminal(task)
  if has('nvim')
    let bufnr = s:GetNvimTaskBufnr(a:task)
    if !empty(bufnr)
      execute 'sbuffer '.bufnr
    endif
    return
  endif

  if s:HasTaskBufnr(a:task)
    execute 'sbuffer '.s:GetTaskBufnr(a:task)
  endif
endfunction

" Forget the started tasks, when quitting a project
function! project#run_tasks#Reset()
  let s:task_state = {}
endfunction

function! s:GetTaskStatus(task)
  if !s:HasTaskBufnr(a:task)
    return ''
  endif

  let bufnr = s:GetTaskBufnr(a:task)
  if has('nvim')
    let status_code = jobwait([bufnr], 0)[0]
    " Fix cursor flashing after nvim v0.10
    redraw
    if status_code == -1
      return 'running'
    else
      return 'finished'
    endif
  else
    return substitute(term_getstatus(bufnr), ',normal', '', '')
  endif
endfunction

function! s:GetTermRows(task)
  return s:HasFilter(a:task) ? s:output_rows * 10 : s:output_rows
endfunction

function! s:OnTaskExit(task_state, job_id, exit_code, ...)
  let a:task_state.exit_code = a:exit_code
  let a:task_state.finished = strftime("%H:%M")
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:RunTask(task, full_cmd)
  let cwd = $vim_project
  if has_key(a:task, 'cd')
    let cwd .= '/'.a:task.cd
  endif
  let options = {
        \'cwd': cwd,
        \'term_name': a:task.name,
        \'term_rows': s:GetTermRows(a:task),
        \'hidden': 1,
        \'term_kill': 'term',
        \}
  let not_started = s:GetTaskStatus(a:task) == ''
  call s:StopTask(a:task)
  let index = project#list#GetCurrentIndex()
  let task_state = s:GetTaskState(a:task)

  if has('nvim')
    execute 'horizontal new'
    set winheight=20
    let options.on_exit = function('s:OnTaskExit', [task_state])
    " for nvim, bufnr is job id
    let task_state.bufnr = termopen(a:full_cmd, options)
    hide
  else
    try
      let options.exit_cb = function('s:OnTaskExit', [task_state])
      let shell_prefix = &shell.' '.&shellcmdflag
      let cmd = shell_prefix.' "'.a:full_cmd.'"'
      let task_state.bufnr = term_start(cmd, options)
    catch
      call project#Warn(v:exception)
      return 0
    endtry
  endif

  let task_state.started = strftime("%H:%M")
  let task_state.started_rel = reltime()

  if not_started
    call project#list#UpdateOffsetByIndex(index - (s:output_rows + 2))
  endif
  return 1
endfunction

function! s:HasFilter(task)
  return has_key(a:task, 'show') || has_key(a:task, 'hide')
endfunction

function! s:StopTask(task)
  let is_prev_running = s:GetTaskStatus(a:task) == 'running'
  let task_state = s:GetTaskState(a:task)
  if !is_prev_running
    if has_key(task_state, 'bufnr')
      unlet task_state.bufnr
    endif
    return
  endif

  if has('nvim')
    call jobstop(task_state.bufnr)
  else
    execute 'bdelete! '.task_state.bufnr
  endif
  unlet task_state.bufnr
endfunction

function! s:FilterRunTasks(tasks, filter)
  return project#util#FuzzyScore(a:tasks, a:filter, ['name', 'cmd'])
endfunction
