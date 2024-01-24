let s:output_rows = 20

function! project#run_tasks#Run()
  call project#PrepareListBuffer('Run a task:', 'RUN_TASKS')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let tasks = project#GetVariable('tasks')
  let max_col_width = project#GetVariable('max_width') / 2 - 10
  call project#Tabulate(tasks, ['name', 'cmd'], 0, max_col_width)
  call s:Update(a:input)
endfunction

function! s:Update(input)
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
  let icon = a:status == 'finished' ? '🏁 🏁 🏁' : '🏃🏃🏃'
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
      if s:HasFilter(task)
        call s:AddTaskOutputWithFilter(task, display, list)
      else
        call s:AddTaskOutput(task, display, list)
      endif
    endif
  endfor
  return [display, list]
endfunction

function! s:AddTaskOutput(task, display, list)
  let line_offset = 0
  let row = term_getcursor(a:task.bufnr)[0]
  for index in range(1, s:output_rows, 1)
    if row < index
      let output = '  '
    else
      let line = term_getline(a:task.bufnr, index + line_offset)
      let output = '  '.line
    endif

    call add(a:display, output)
    let item = {'name': a:task.name, 'cmd': a:task.cmd, 'output': output}
    call add(a:list, item)
  endfor
endfunction

function! s:AddTaskOutputWithFilter(task, display, list)
  let [rows, cols] = term_getsize(a:task.bufnr)
  let output_count = 0
  let output_list_backward = []
  for index in range(rows, 1, -1)
    if output_count > s:output_rows - 2
      break
    endif

    let line = term_getline(a:task.bufnr, index)
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
  let tasks = s:FilterRunTasks(copy(project#GetVariable('tasks')), a:input)
  let [display, list] = s:GetRunTasksDisplay(tasks)
  call project#SetVariable('list', list)
  call project#ShowInListBuffer(display, a:input)

  " Move to near task row
  if project#GetVariable('offset') == 0 && getline('.') !~ '^\w'
    call project#UpdateOffsetByIndex(search('^\w', 'bnW') - 1)
  endif

  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call s:HighlightRunTasksCmdOutput()
  call project#HighlightNoResults()
  redraw
endfunction

function! s:HighlightRunTasksCmdOutput()
  match InfoRow /^\s\{2,}.*/
  2match Status '\[running.*\]'
  3match Special '\[finished.*\]'
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:Open(task, open_cmd, input)
  if a:open_cmd == 'open_task_terminal'
    return s:OpenTaskTerminal(a:task)
  endif

  " Open vim terminal if the task has empty cmd
  if s:hasEmptyTaskCmd(a:task)
    if a:open_cmd == '@pass'
      return 0
    endif

    if has('nvim')
      new
      cd $vim_project
      terminal
      startinsert
    else
      terminal ++kill=kill
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

function! s:GetNvimTaskBufnr(task)
  let job_id = a:task.bufnr
  for buffer in getbufinfo({'buflisted': 1})
    if has_key(buffer.variables, 'terminal_job_id') && buffer.variables.terminal_job_id == job_id
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

  execute 'sbuffer '.a:task.bufnr
endfunction

function! project#run_tasks#reset()
  call s:WipeoutTaskBuffer()
endfunction

function! s:WipeoutTaskBuffer()
  let tasks = project#GetVariable('tasks')
  for task in tasks
    if has_key(task, 'bufnr')
      unlet task.bufnr
    endif
  endfor
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

function! s:GetTermRows(task)
  return s:HasFilter(a:task) ? s:output_rows * 10 : s:output_rows
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
        \'term_rows': s:GetTermRows(a:task),
        \'hidden': 1,
        \'term_kill': 'term',
        \}
  let has_started = s:GetTaskStatus(a:task) != ''
  call s:StopTask(a:task)

  let shell_prefix = &shell.' '.&shellcmdflag
  let cmd = shell_prefix.' "'.a:task.cmd.'"'

  if has('nvim')
    enew
    set winheight=20
    let a:task.bufnr = termopen(cmd, options)
    return 0
  endif

  let index = project#GetCurrentIndex()
  try 
    let a:task.bufnr = term_start(cmd, options)
  catch
    call project#Warn(v:exception)
    return 0
  endtry

  if !has_started
    call project#UpdateOffsetByIndex(index - (s:output_rows + 1))
  endif
  return 1
endfunction

function! s:HasFilter(task)
  return has_key(a:task, 'show') || has_key(a:task, 'hide')
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

function! project#run_tasks#StopTaskHandler(input)
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

