let s:run_tasks_output_rows = 15

function! project#run_tasks#run()
  call project#PrepareListBuffer('Run a task:', 'RUN_TASKS')
  let Init = function('s:RunTasksBufferInit')
  let Update = function('s:RunTasksBufferUpdateTimerManager')
  let Open = function('s:RunTasksBufferOpen')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:RunTasksBufferInit(input)
  let tasks = project#GetVariable('tasks')
  let max_col_width = project#GetVariable('max_width') / 2 - 10
  call project#TabulateList(tasks, ['name', 'cmd'], [], 0, max_col_width)
  call s:RunTasksBufferUpdateTimerManager(a:input)
endfunction

function! s:RunTasksBufferUpdateTimerManager(input)
  call project#run_tasks#StopRunTasksTimer()
  call s:RunTasksBufferUpdate(a:input)
  let s:run_tasks_timer = timer_start(500, function('s:RunTasksBufferUpdateTimer', [a:input]),
        \{'repeat': -1})
endfunction

function! project#run_tasks#Highlight()
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

function! project#run_tasks#StopRunTasksTimer()
  if !exists('s:run_tasks_timer')
    return
  endif
  call timer_stop(s:run_tasks_timer)
endfunction

function! s:RunTasksBufferUpdateTimer(input, id)
  call s:RunTasksBufferUpdate(a:input)
endfunction

function! s:GetTaskStatusLine(status)
  let icon = a:status == 'finished' ? '🏁' : '🏃'
  return '  ['.a:status.'] '.icon
endfunction

function! s:GetRunTasksDisplay(tasks)
  let display = []
  let list = []

  for task in a:tasks
    if has_key(task, '__name')
      let task_row = task.__name.'  '.task.__cmd
      if has_key(task, 'cd')
        let task_row .= '  (cd '.task.cd.')'
      endif
      call add(display, task_row)
      call add(list, task)
    endif

    if has_key(task, 'bufnr') && task.bufnr > 0
      let status = s:GetTaskStatus(task)
      if status == ''
        continue
      endif

      " Add task status
      let output = s:GetTaskStatusLine(status)
      let item = {'name': task.name, 'cmd': task.cmd, 'output': output}
      call add(display, output)
      call add(list, item)

      if has('nvim')
        continue
      endif

      " Add task output
      let [row, col, dict] = term_getcursor(task.bufnr)
      for idx in range(1, s:run_tasks_output_rows, 1)
        if row - idx < 0
          let output = '  '
        else
          let line = term_getline(task.bufnr, idx)
          let output = '  '.line
        endif
        let item = {'name': task.name, 'cmd': task.cmd, 'output': output}
        call add(display, output)
        call add(list, item)
      endfor
    endif
  endfor
  return [display, list]
endfunction

function! s:RunTasksBufferUpdate(input)
  let tasks = s:FilterRunTasks(copy(project#GetVariable('tasks')), a:input)
  let [display, list] = s:GetRunTasksDisplay(tasks)
  call project#SetVariable('list', list)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call s:HighlightRunTasksCmdOutput()
  call project#HighlightNoResults()
  if empty(a:input)
    call project#RedrawEmptyInputLine()
  else
    call project#RedrawInputLine()
  endif
endfunction

function! s:HighlightRunTasksCmdOutput()
  match InfoRow /^\s\{2,}.*/
  2match Status '\[running.*\]'
  3match Special '\[finished.*\]'
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:RunTasksBufferOpen(task, open_cmd, input)
  if a:open_cmd == 'open_task_terminal'
    return s:OpenTaskTerminal(a:task)
  endif

  " Open vim terminal if the task has empty cmd
  if s:hasEmptyTaskCmd(a:task)
    if a:open_cmd == '@pass'
      return 0
    endif

    terminal
    if !has('nvim')
      call term_sendkeys(bufnr('%'), "cd $vim_project\<CR>")
      call term_sendkeys(bufnr('%'), "clear\<CR>")
    endif
    return 0
  endif

  return s:RunTask(a:task)
endfunction

function! s:hasEmptyTaskCmd(task)
  return !has_key(a:task, 'cmd') || a:task.cmd == ''
endfunction

function! s:OpenTaskTerminal(task)
  if has('nvim')
    return
  endif

  execute 'sbuffer '.a:task.bufnr
endfunction

function! s:GetTaskStatus(task)
  if !has_key(a:task, 'bufnr')
    return ''
  endif

  if has('nvim')
    let status_code = jobwait([a:task.bufnr], 0)[0]
    if status_code == -1
      return 'running'
    else
      return 'finished'
    endif
  else
    return substitute(term_getstatus(a:task.bufnr), ',normal', '', '')
  endif
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:RunTask(task)
  let cwd = $vim_project
  if has_key(a:task, 'cd')
    let cwd .= '/'.a:task.cd
  endif

  let options = { 
        \'cwd': cwd,
        \'term_name': a:task.name,
        \'term_rows': s:run_tasks_output_rows,
        \'hidden': 1,
        \}
  let has_prev_buf = s:GetTaskStatus(a:task) != ''
  call s:StopTask(a:task)

  if has('nvim')
    enew
    set winheight=20
    let a:task.bufnr = termopen(a:task.cmd, options)
    return 0
  endif

  let index = project#GetCurrentIndex()
  let a:task.bufnr = term_start(a:task.cmd, options)

  if !has_prev_buf
    call project#UpdateOffsetByIndex(index - (s:run_tasks_output_rows + 1))
  endif
  return 1
endfunction

function! s:StopTask(task)
  let is_prev_running = s:GetTaskStatus(a:task) == 'running'
  if !is_prev_running
    if has_key(a:task, 'bufnr')
      unlet a:task.bufnr
    endif
    return
  endif

  if has('nvim')
    call jobstop(a:task.bufnr)
  else
    execute 'bdelete! '.a:task.bufnr
  endif
  unlet a:task.bufnr
endfunction

function! s:StopTaskHandler(input)
  let index = project#GetCurrentIndex()
  let task = project#GetTarget()
  call s:StopTask(task)
  call s:RunTasksBufferUpdate(a:input)
  call project#UpdateOffsetByIndex(index)
endfunction

function! s:FilterRunTasks(tasks, filter)
  let regexp_filter = join(split(a:filter, '\zs'), '.*')

  for task in a:tasks
    let task._match_type = ''
    let task._match_index = -1

    let match_index = match(task.name, regexp_filter)
    if match_index != -1
      " Prefer exact match. If not, add 10 to match_index
      if len(a:filter) > 1 && count(tolower(task.name), a:filter) == 0
        let match_index = match_index + 10
      endif
      let task._match_type = 'name'
      let task._match_index = match_index
    endif

    if match_index == -1
      let match_index = match(task.cmd, regexp_filter)
      if match_index != -1
        let task._match_type = 'cmd'
        let task._match_index = match_index
      endif
    endif
  endfor

  let result = filter(a:tasks, { _, val -> val._match_type != '' })
  call sort(result, 's:SortRunTasks')
  return result
endfunction

function! s:SortRunTasks(a1, a2)
  let type1 = a:a1._match_type
  let type2 = a:a2._match_type
  let index1 = a:a1._match_index
  let index2 = a:a2._match_index

  if type1 == 'name' && type2 != 'name'
    return 1
  endif

  if type1 == type2
    return index2 - index1
  endif

  return -1
endfunction

