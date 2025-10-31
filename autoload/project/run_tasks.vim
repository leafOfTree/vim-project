let s:output_rows = 20
let s:terminal_bufnr = -1

function! project#run_tasks#Run()
  call project#PrepareListBuffer('Run a task:', 'RUN_TASKS')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let tasks = project#GetVariable('tasks')
  let max_col_width = project#GetVariable('max_width') - 10
  call project#Tabulate(tasks, ['name'], 0, max_col_width)
  call s:FilterEmptyTask(tasks)
  call s:Update(a:input)
endfunction

function! s:Update(input)
  call project#run_tasks#StopRunTasksTimer()
  call s:RunTasksBufferUpdate(a:input)
  call s:StartRunTasksTimers(a:input)
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

function! s:FilterEmptyTask(tasks)
  call filter(a:tasks, 
        \{idx, task -> !s:HasEmptyName(task) || !s:HasEmptyCmd(task)})
endfunction

function! s:StartRunTasksTimers(input)
  let s:run_tasks_timer = timer_start(500, function('s:RunTasksBufferUpdateTimer', [a:input]),
        \{'repeat': -1})
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

function! s:GetTaskStatusLine(task, status)
  if a:status == 'finished'
    let error = s:HasTaskExitCode(a:task) && a:task.exit_code
    if error
      let icon = '❌ '.a:task.exit_code
    else
      let icon = '✅ '
    endif
  else
    let icon = '🏃' " 🔄
    let duration_full = split(reltimestr(reltime(a:task.started_rel)))[0]
    let a:task.duration = substitute(duration_full, '\..*', '', 'g')
  endif
  

  let width = &columns
  let left = '  ['.a:status.'] '.icon
  if has_key(a:task, 'duration')
    let right = a:task.duration.'s'
  else
    let right = ''
  endif
  if a:status == 'finished'
    if has_key(a:task, 'finished')
      let right = 'At '.a:task.finished.', '.right
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
    if has_key(task, '__name')
      let task_row = task.__name
      let task_row .= '  '.task.cmd
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

function! s:HasTaskExitCode(task)
  return has_key(a:task, 'exit_code')
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
  let rows = term_getcursor(a:task.bufnr)[0]
  for index in range(1, s:output_rows + 1, 1)
    if index > rows
      let output = '  '
    else
      let line = term_getline(a:task.bufnr, index)
      let output = '  '.line
    endif
    call s:AddTaskOutput(output, a:task, a:display, a:list)
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
  call project#HighlightNoResults()
  call s:HighlightRunTasksCmdOutput()

  call project#SetVariable('user_input', a:input)
  call project#RedrawInputLine()
endfunction

function! s:HighlightRunTasksCmdOutput()
  match InfoRow /^\s\{2,}.*/
  2match Status '\[running.*\]'
  3match Special '\[finished.*\]'
  call matchadd('Comment', 'At.*s$')
  call matchadd('Comment', '   \d\+s$')
endfunction

" @return:
"   1: keep current window,
"   0: exit current window
function! s:Open(task, open_cmd, input)
  if a:open_cmd == 'open_task_terminal'
    return s:OpenTaskTerminal(a:task)
  endif

  " Open vim terminal if the task has empty cmd
  if s:HasEmptyCmd(a:task)
    if a:open_cmd == '@pass'
      return 0
    endif

    call s:OpenTerminal()
    return 0
  endif

  let cmd = a:task.cmd
  if s:HasArgs(a:task)
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

function! s:HasArgs(task)
  return has_key(a:task, 'args')
endfunction

function! s:GetNvimTaskBufnr(task)
  if !has_key(a:task, 'bufnr')
    return 0
  endif
  let job_id = a:task.bufnr
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
    " Fix cursor flashing after nvim v0.10
    redraw
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

function! s:OnTaskExit(task, job_id, exit_code, ...)
  let a:task.exit_code = a:exit_code
  let a:task.finished = strftime("%H:%M")
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
  let index = project#GetCurrentIndex()

  if has('nvim')
    horizontal new
    set winheight=20
    let options.on_exit = function('s:OnTaskExit', [a:task])
    " for nvim, bufnr is job id
    let a:task.bufnr = termopen(a:full_cmd, options)
    hide
  else
    try 
      let options.exit_cb = function('s:OnTaskExit', [a:task])
      let shell_prefix = &shell.' '.&shellcmdflag
      let cmd = shell_prefix.' "'.a:full_cmd.'"'
      let a:task.bufnr = term_start(cmd, options)
    catch
      call project#Warn(v:exception)
      return 0
    endtry
  endif

  let a:task.started = strftime("%H:%M")
  let a:task.started_rel = reltime()

  if not_started
    call project#UpdateOffsetByIndex(index - (s:output_rows + 2))
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

function! project#run_tasks#DumpTasks()
  let tasks = project#GetVariable('tasks')
  return deepcopy(tasks)
endfunction

function! project#run_tasks#RebindTasks(old_tasks)
  let tasks = project#GetVariable('tasks')
  for old_task in a:old_tasks
    if has_key(old_task, 'bufnr')
      for task in tasks
        if task.name == old_task.name
          let task.bufnr = old_task.bufnr
          let task.started = old_task.started
          let task.started_rel = old_task.started_rel
          let task.duration = old_task.duration
          if has_key(old_task, 'exit_code')
            let task.exit_code = old_task.exit_code
          endif
          if has_key(old_task, 'finished')
            let task.finished = old_task.finished
          endif
        endif
      endfor
    endif
  endfor
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

