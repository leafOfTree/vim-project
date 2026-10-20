" The list UI shared by every list of vim-project: a window at the bottom
" showing items, a prompt line, and a key loop that filters as the user types.
"
" A module opens a list with project#list#Open(spec). The spec keys are
"
"   type            string. Identifies the list, also the key of its history
"   prompt          string shown before the input
"   mappings        dict command -> key or [keys]. List specific keys, looked
"                   up before the global list_mappings
"   Init            funcref(input). Load the items. May return a string to
"                   replace the initial input
"   Update          funcref(input). Filter and show the items
"   Open            funcref(target, cmd, input). Called after the list has
"                   closed by an open command
"   Close           funcref(). Optional. Called after the list has closed by
"                   anything else
"   handlers        dict command -> funcref(state). Optional. List specific
"                   commands. A handler may change state.user_input, and
"                   returns an action:
"                     '' or 0   keep the list open and update it
"                     'close'   close the list
"                     'open'    close the list, then call Open with the command
"                     'switch'  leave the list window open like switch_to_list
"   ItemStep        funcref(direction). Optional. Lines to move for
"                   prev_item (-1) or next_item (1). Default 1
"   Highlight       funcref(state). Optional. Called after the default
"                   highlight links to set list specific ones and
"                   state.first_column_pattern
"   save_history    number or funcref(input). Optional. Whether to save input,
"                   offset and height when closing, to restore next time
"   init_input      string. Optional. Start with this input
"   initial_height  number. Optional. Window height before the first update
"
" Commands handled here: close_list, clear_char, clear_word, clear_all,
" prev_item, next_item, first_item, last_item, scroll_up, scroll_down, paste,
" switch_to_list and any command starting with "open". Other commands go to
" spec.handlers.
"
" The list state is a dict, from project#list#State() while a list is open:
"
"   list              the items currently shown. Set by Update
"   offset            0, -1, -2 ... selected item counted from the bottom
"   input             the input of the last query, -1 before the first one
"   replace           the replace part of the last query, -1 if none
"   user_input        the input typed so far
"   init_input        spec.init_input
"   from_history      1 when the input was restored from history
"   initial_height    window height
"   max_width         available columns
"   max_height        available lines
"   column_pattern    regexp of one column
"   first_column_pattern, second_column_pattern
"   history           dict type -> saved state of closed lists

let s:list_buffer = 'vim_project_list'
let s:list_history = {}
let s:state = {}
let s:spec = {}
let s:info_on_close = ''

let s:note_prefix = '- '
let s:column_pattern = '\S*\(\s\S\+\)*'
let s:note_column_pattern = '\(\s\{2,}'.s:note_prefix.s:column_pattern.'\)\?'
let s:second_column_pattern = '\s\{2,}[^- ]'.s:column_pattern

function! project#list#Open(spec)
  let s:spec = a:spec
  let s:state = {
        \'list': [],
        \'offset': 0,
        \'input': -1,
        \'replace': -1,
        \'user_input': '',
        \'init_input': get(a:spec, 'init_input', ''),
        \'from_history': 0,
        \'initial_height': get(a:spec, 'initial_height', 0),
        \'max_width': &columns,
        \'max_height': winheight(0) - 10,
        \'column_pattern': s:column_pattern,
        \'first_column_pattern': '^'.s:column_pattern.s:note_column_pattern,
        \'second_column_pattern': s:second_column_pattern,
        \'history': s:list_history,
        \}
  let s:laststatus_save = &laststatus
  let s:ruler_save = &ruler

  " Manually trigger some events first
  silent doautocmd BufLeave
  silent doautocmd FocusLost

  " Ignore events to avoid a cursor bug when opening from Fern.vim
  let save_eventignore = &eventignore
  set eventignore=all
  " Events must come back even after an error, or autocmds stay off
  try
    call s:OpenListBuffer()
    call s:SetupListBuffer()
  finally
    let &eventignore = save_eventignore
  endtry

  call s:RenderList()
endfunction

function! project#list#State()
  return s:state
endfunction

function! project#list#GetHistory(type)
  return get(s:list_history, a:type, {})
endfunction

function! project#list#ClearHistory()
  let s:list_history = {}
endfunction

" Show the message after the list has closed, with the buffer reloaded
function! project#list#SetInfoOnClose(msg)
  let s:info_on_close = a:msg
endfunction

function! s:InfoOnClose()
  if empty(s:info_on_close)
    return
  endif
  edit
  call project#Info(s:info_on_close)
  let s:info_on_close = ''
endfunction

function! s:OpenListBuffer()
  let win = s:list_buffer
  let num = bufwinnr(win)
  if num == -1
    execute 'silent botright split '.win
  else
    execute num.'wincmd w'
  endif
endfunction

function! s:CloseListBuffer(action)
  let &g:laststatus = s:laststatus_save
  let &g:ruler = s:ruler_save

  if !s:IsCurrentListBuffer() || a:action == 'switch'
    return
  endif

  call s:ClearMessageArea()
  quit
  wincmd p
endfunction

function! s:ClearMessageArea()
  if exists("g:neovide")
    echon "\r\r"
    echon ''
  else
    call inputsave()
    call feedkeys(':', 'nx')
    call inputrestore()
  endif
endfunction

function! project#list#Wipeout()
  let num = bufnr(s:list_buffer)
  if num != -1
    execute 'silent bwipeout! '.num
  endif
endfunction

function! s:SetupListBuffer()
  if !s:IsCurrentListBuffer()
    return
  endif

  setlocal buftype=nofile bufhidden=delete nobuflisted
  setlocal filetype=vimprojectlist
  setlocal nonumber
  setlocal nocursorline
  setlocal nowrap
  set noruler
  set laststatus=0

  highlight link FirstColumn Normal
  highlight link SecondColumn Comment
  if has_key(s:spec, 'Highlight')
    call s:spec.Highlight(s:state)
  endif

  syntax clear
  execute 'syntax match InfoRow /^\s\{2,}.*/'
  execute 'syntax match SecondColumn /'.s:state.second_column_pattern.'/'
  execute 'syntax match FirstColumn /'.s:state.first_column_pattern.'/'

  highlight link ItemSelected CursorLine
  highlight! link SignColumn Noise
  call project#list#DefineDistinctHighlight('VimProjectMatch',
        \['Constant', 'Special', 'Function', 'Identifier', 'String', 'Statement'])
  highlight link InputChar VimProjectMatch

  call s:HighlightWithBgBasedOn('Comment', 0, 0, 'BeforeReplace')
  call s:HighlightWithBgBasedOn('Function', 0, 'bold', 'AfterReplace')

  sign define selected text=> texthl=ItemSelected linehl=ItemSelected
endfunction

" Define a:group in bold with the first color of a:candidates that differs
" from Normal, or underlined if none does. Linking to one group, e.g.
" Constant, made text invisible where it looks like Normal (Neovim 0.10+
" default colors). 'default' keeps a definition of the user, and a
" :colorscheme clears ours, so it is worked out again for the new colors
function! project#list#DefineDistinctHighlight(group, candidates)
  let normal = s:GetColors('Normal')
  let colors = {}
  for group in a:candidates
    let candidate = s:GetColors(group)
    if (!empty(candidate.gui) && candidate.gui !=? normal.gui)
          \|| (empty(candidate.gui) && !empty(candidate.cterm) && candidate.cterm != normal.cterm)
      let colors = candidate
      break
    endif
  endfor

  if empty(colors)
    execute 'highlight default' a:group 'term=bold,underline cterm=bold,underline gui=bold,underline'
    return
  endif
  execute 'highlight default' a:group 'term=bold cterm=bold gui=bold'
        \.(empty(colors.cterm) ? '' : ' ctermfg='.colors.cterm)
        \.(empty(colors.gui) ? '' : ' guifg='.colors.gui)
endfunction

function! s:GetColors(group)
  let id = synIDtrans(hlID(a:group))
  return {'gui': synIDattr(id, 'fg#', 'gui'), 'cterm': synIDattr(id, 'fg', 'cterm')}
endfunction

function! s:HighlightWithBgBasedOn(base_group, bg_group, attr, new_group)
  let ctermfg = s:GetArgValue(a:base_group, 'fg', 'cterm')
  let ctermbg = s:GetArgValue(a:base_group, 'bg', 'cterm')
  let guifg = s:GetArgValue(a:base_group, 'fg', 'gui')
  let guibg = s:GetArgValue(a:base_group, 'bg', 'gui')

  if !empty(a:base_group)
    let ctermbg_default = s:GetArgValue(a:bg_group, 'bg', 'cterm')
    let guibg_default = s:GetArgValue(a:bg_group, 'bg', 'gui')
    if empty(ctermbg)
      let ctermbg = ctermbg_default
    endif

    if empty(guibg)
      let guibg = guibg_default
    endif
  endif

  let highlight_cmd = 'highlight '.a:new_group

  if !empty(a:attr)
    let highlight_cmd .= ' term='.a:attr.' cterm='.a:attr.' gui='.a:attr
  endif

  if !empty(ctermfg)
    let highlight_cmd .= ' ctermfg='.ctermfg
  endif
  if !empty(ctermbg)
    let highlight_cmd .= ' ctermbg='.ctermbg
  endif

  if !empty(guifg)
    let highlight_cmd .= ' guifg='.guifg
  endif
  if !empty(guibg)
    let highlight_cmd .= ' guibg='.guibg
  endif

  execute highlight_cmd
endfunction

function! s:GetArgValue(name, what, mode)
  return synIDattr(synIDtrans(hlID(a:name)), a:what, a:mode)
endfunction

function! s:IsCurrentListBuffer()
  return expand('%') == s:list_buffer
endfunction

function! project#list#IsCurrentListBuffer()
  return s:IsCurrentListBuffer()
endfunction

" Whether the list of a:type is open and focused, e.g. for async updates
function! project#list#IsOpen(type)
  return s:IsCurrentListBuffer() && get(s:spec, 'type', '') ==# a:type
endfunction

function! project#list#HighlightCurrentLine(list_length)
  let length = a:list_length
  sign unplace 9
  if length > 0
    if s:state.offset > 0
      let s:state.offset = 0
    endif
    if s:state.offset < 1 - length
      let s:state.offset = 1 - length
    endif

    let current = length + s:state.offset

    if length < s:state.initial_height
      " Add extra empty liens to keep initial height
      let current += s:state.initial_height - length
    endif
    execute 'sign place 9 line='.current.' name=selected'
  endif

  if length > s:state.max_height
    normal! G
    execute 'normal! '.string(current).'G'
  endif
endfunction

function! project#list#Show(display, input)
  " Avoid clearing other files by mistake
  if !s:IsCurrentListBuffer()
    return
  endif

  call s:AddToListBuffer(a:display, a:input)
  let length = len(a:display)
  call s:AdjustHeight(length, a:input)
  call s:AddEmptyLines(length)
  call s:RemoveNeovideAnimation()
  call s:RemoveExtraBlankLineAtBottom()
endfunction

function! s:RemoveExtraBlankLineAtBottom()
  silent normal! G"_dd
  normal! gg
  normal! G
endfunction

function! s:AddToListBuffer(display, input)
  normal! gg"_dG
  if len(a:display) > 0
    call append(0, a:display)
  else
    if len(a:input) > 1
      call append(0, '- No results for: '.a:input)
    endif
  endif
endfunction

function! s:AdjustHeight(length, input)
  if (a:length == 0 && a:input == '') || a:length > s:state.max_height
    let s:state.initial_height = s:state.max_height
  elseif a:input == '' && s:state.initial_height == 0
    let s:state.initial_height = a:length
  elseif a:length > s:state.initial_height && a:length < s:state.max_height
    let s:state.initial_height = a:length
  endif

  if winheight(0) != s:state.initial_height
    execute 'resize '.s:state.initial_height
  endif
endfunction

function! s:AddEmptyLines(current)
  if a:current < s:state.initial_height
    let counts = s:state.initial_height - a:current
    call append(0, repeat([''], counts))
  endif
endfunction

function! s:AddRightPadding(string, length)
  if strdisplaywidth(a:string) > a:length
    return a:string
  endif

  let padding = repeat(' ', a:length - strdisplaywidth(a:string) + 1)
  return a:string.padding
endfunction

" Return one dict per item with each key padded or truncated to its width.
" The items are not changed
function! project#list#TabulateFixed(list, keys, widths)
  let columns = []
  for item in a:list
    let column = {}
    let key_idx = 0
    for key in a:keys
      if strdisplaywidth(item[key]) > a:widths[key_idx]
        let column[key] = s:Truncate(item[key], a:widths[key_idx], '.. ')
      else
        let column[key] = s:AddRightPadding(item[key], a:widths[key_idx])
      endif

      let key_idx = key_idx + 1
    endfor
    call add(columns, column)
  endfor
  return columns
endfunction

" Return one dict per item with each key padded to the width of its column.
" Only keys the item has are included. The items are not changed
function! project#list#Tabulate(list, keys, ...)
  let min_col_width = get(a:000, 0, 0)
  let max_col_width = get(a:000, 1, &columns)
  " Init max width of each column
  let max = {}
  let columns = []

  " Get max width of each column
  for item in a:list
    let column = {}
    for key in a:keys
      if has_key(item, key)
        let value = project#ReplaceHomeWithTide(item[key])
        let column[key] = value

        if !has_key(max, key) || strdisplaywidth(value) > max[key]
          let max[key] = strdisplaywidth(value)
        endif
      endif
    endfor
    call add(columns, column)
  endfor

  " If necessary, trim value that is too long
  let max_width = 0
  for value in values(max)
    let max_width += value
  endfor
  if max_width > s:state.max_width
    let max = {}
    for column in columns
      for key in a:keys
        if has_key(column, key)
          let value = column[key]
          if strdisplaywidth(value) > max_col_width
            let value = s:Truncate(value, max_col_width, '..')
            let column[key] = value
          endif
          if !has_key(max, key) || strdisplaywidth(value) > max[key]
            let max[key] = strdisplaywidth(value)
          endif
        endif
      endfor
    endfor
  endif

  " Add right padding
  for column in columns
    for key in a:keys
      if has_key(column, key)
        let max_width = max([max[key], min_col_width])
        let column[key] = s:AddRightPadding(column[key], max_width)
      endif
    endfor
  endfor

  return columns
endfunction

" Cut by display width (not bytes) so multibyte text is never split
function! s:Truncate(value, max_width, placeholder)
  let width = a:max_width - strdisplaywidth(a:placeholder) + 1
  let result = ''
  for char in split(a:value, '\zs')
    if strdisplaywidth(result.char) > width
      break
    endif
    let result .= char
  endfor
  return result.a:placeholder
endfunction

function! s:GetListCommand(char)
  " the first takes effect
  let list_mappings = [get(s:spec, 'mappings', {}), project#config#Get('list_mappings')]

  for mappings in list_mappings
    for [command, value] in items(mappings)
      if type(value) == v:t_string
        let match = value == a:char
      else
        let match = count(value, a:char) > 0
      endif

      if match
        return command
      endif
    endfor
  endfor
  return ''
endfunction

function! project#list#HighlightNoResults()
  call matchadd('Comment', '^- No results for:.*')
endfunction

function! s:ShowInputLine(input)
  redraw
  " Fix cursor flashing when in terminal,
  echo ''
  " The second space is unicode space that looks like space
  let input = substitute(a:input, ' $', ' ', '')
  echo s:spec.prompt.' '.input
endfunction

function! project#list#RedrawInputLine()
  call s:ShowInputLine(s:state.user_input)
endfunction

function! project#list#HighlightExtraInfo()
  1match String /  ...more$/
endfunction

function! s:ShowInitialInputLine(input, ...)
  mode
  call s:ShowInputLine(a:input)
endfunction

function! s:RenderList()
  let action = 'close'
  let cmd = ''
  let input = ''
  let error = ''
  try
    let input = s:InitListVariables()
    call s:ShowInitialInputLine(input)
    let [action, cmd, input] = s:HandleInput(input)
  catch
    let action = 'error'
    let error = v:exception.' ('.v:throwpoint.')'
  finally
    " Always close the list and restore laststatus/ruler
    call s:CloseListBuffer(action)
    call s:RecoverNeovideAnimation()
  endtry
  if !empty(error)
    call project#Warn(error)
  endif

  if action == 'open'
    call s:OpenTarget(cmd, input)
  endif
  call s:SaveListState(input)
  call s:ResetListVariables()
  if action != 'open' && has_key(s:spec, 'Close')
    call s:spec.Close()
  endif
  call s:InfoOnClose()
endfunction

function! s:InitListVariables()
  let type = s:spec.type
  let has_init_input = !empty(s:state.init_input)
  let has_history = has_key(s:list_history, type)
  if has_init_input
    let input = s:state.init_input
    let s:state.offset = 0
    let s:state.initial_height = s:state.max_height
    let s:state.init_input = ''
  elseif has_history
    let history = s:list_history[type]
    let input = history.input
    let s:state.offset = history.offset
    let s:state.initial_height = history.initial_height
    let s:state.from_history = 1
  else
    let input = ''
    let s:state.offset = 0
  endif

  " Make sure state.input (saved input), state.replace (saved replace)
  " is differrent from input to trigger query
  let s:state.input = -1
  let s:state.replace = -1
  let s:state.list = []
  let s:state.user_input = input

  let Result = s:spec.Init(input)
  if type(Result) == v:t_string
    let input = Result
    let s:state.user_input = input
  endif

  return input
endfunction

function! s:GetUserInputChar()
  let c = getchar()
  let char = type(c) == v:t_string ? c : nr2char(c)
  return char
endfunction

function! s:ClearCharOfInput(input)
  return strcharpart(a:input, 0, strchars(a:input) - 1)
endfunction

function! s:ClearWordOfInput(input)
  if a:input =~ '\w\s*$'
    let input = substitute(a:input, '\w*\s*$', '', '')
  else
    let input = substitute(a:input, '\W*\s*$', '', '')
  endif
  return input
endfunction

function! s:IsOpenCmd(cmd)
  return a:cmd =~ '^open'
endfunction

" Return [action, cmd, input]. action is one of
" 'close', 'open', 'switch' or 'interrupt'
function! s:HandleInput(input)
  let input = a:input
  let action = 'close'
  let cmd = ''
  let handlers = get(s:spec, 'handlers', {})

  try
    while 1
      let char = s:GetUserInputChar()
      let cmd = s:GetListCommand(char)
      if has_key(handlers, cmd)
        let s:state.user_input = input
        let action = handlers[cmd](s:state)
        let input = s:state.user_input
        if !empty(action)
          break
        endif
      elseif cmd == 'close_list'
        let action = 'close'
        break
      elseif cmd == 'clear_char'
        let input = s:ClearCharOfInput(input)
      elseif cmd == 'clear_word'
        let input = s:ClearWordOfInput(input)
      elseif cmd == 'clear_all'
        let input = ''
      elseif cmd == 'prev_item'
        call s:MoveItem(-1)
      elseif cmd == 'next_item'
        call s:MoveItem(1)
      elseif cmd == 'first_item'
        let s:state.offset = 1 - len(s:state.list)
      elseif cmd == 'last_item'
        let s:state.offset = 0
      elseif cmd == 'scroll_up'
        let s:state.offset = s:state.offset - winheight(0)/2
      elseif cmd == 'scroll_down'
        let s:state.offset = s:state.offset + winheight(0)/2
      elseif cmd == 'paste'
        let input .= @*
      elseif cmd == 'switch_to_list'
        let action = 'switch'
        break
      elseif s:IsOpenCmd(cmd)
        let action = 'open'
        break
      else
        let input = input.char
      endif

      call s:spec.Update(input)
      let s:state.user_input = input
      call s:ShowInputLine(input)
    endwhile
  catch /^Vim:Interrupt$/
    let action = 'interrupt'
  endtry

  return [action, cmd, input]
endfunction

function! s:RemoveNeovideAnimation()
  if !exists("g:neovide") || g:neovide_scroll_animation_length == 0
    return
  endif

  let s:neovide_scroll_animation_length = g:neovide_scroll_animation_length
  let g:neovide_scroll_animation_length = 0
endfunction

function! s:RecoverNeovideAnimation()
  if !exists("g:neovide") || !exists('s:neovide_scroll_animation_length')
    return
  endif
  let g:neovide_scroll_animation_length = s:neovide_scroll_animation_length
  unlet s:neovide_scroll_animation_length
endfunction

" direction: -1 for prev_item, 1 for next_item
function! s:MoveItem(direction)
  let step = has_key(s:spec, 'ItemStep') ? s:spec.ItemStep(a:direction) : 1
  let s:state.offset += a:direction * step
endfunction

function! project#list#GetCurrentLineNumber()
  if winheight(0) > len(s:state.list)
    return winheight(0) - len(s:state.list) + project#list#GetCurrentIndex() + 1
  endif

  return project#list#GetCurrentIndex() + 1
endfunction

function! s:ShouldSaveListState(input)
  let Save = get(s:spec, 'save_history', 0)
  if type(Save) == v:t_func
    return Save(a:input)
  endif
  return Save
endfunction

function! s:SaveListState(input)
  if !s:ShouldSaveListState(a:input)
    return
  endif

  let s:list_history[s:spec.type] = {
        \'input': a:input,
        \'offset': s:state.offset,
        \'initial_height': s:state.initial_height,
        \}
endfunction

function! s:ResetListVariables()
  unlet! s:state.input
  unlet! s:state.list
  let s:state.initial_height = 0
endfunction

function! project#list#GetTarget()
  let index = len(s:state.list) - 1 + s:state.offset

  if index >= 0 && index < len(s:state.list)
    let target = s:state.list[index]
    return target
  endif

  return {}
endfunction

" index: 0,1,2,... from top to bottom
function! project#list#GetCurrentIndex()
  return len(s:state.list) - 1 + s:state.offset
endfunction

" offset: 0,1,2,... from bottom to top
" index: 0,1,2,... from top to bottom
function! project#list#UpdateOffsetByIndex(index)
  if a:index < len(s:state.list) - 1
    let s:state.offset = a:index - len(s:state.list) + 1
  else
    let s:state.offset = 0
  endif
endfunction

function! s:OpenTarget(cmd, input)
  let target = project#list#GetTarget()

  if empty(target)
    call project#Warn('No item selected')
    return
  endif

  return s:spec.Open(target, a:cmd, a:input)
endfunction

function! project#list#IsShowHistoryList(input)
  return a:input == '' && s:state.input == -1 && !empty(s:state.list)
endfunction

" Highlight each word of a:input where it appears, for lists filtered by
" words rather than by characters in order
function! project#list#HighlightInputWords(input)
  call clearmatches()
  for word in split(a:input, ' ')
    call matchadd('InputChar', '\V'.escape(word, '\'))
  endfor
endfunction

function! project#list#HighlightInputChars(input)
  call clearmatches()
  if empty(a:input)
    return
  endif
  for lnum in range(max([line('$') - 100, 0]), line('$'))
    let pos = s:GetMatchPos(lnum, a:input)
    if len(pos) == 0
      continue
    endif

    " The maximum number of positions in {pos} is 8.
    for i in range(0, len(pos), 8)
      if empty(pos[i:i+7])
        continue
      endif
      call matchaddpos('InputChar', pos[i:i+7])
    endfor
  endfor
endfunction

" Try columns one by one
function! s:GetMatchPos(lnum, input)
  if empty(a:input)
    return []
  endif

  let search = split(a:input, '\zs')
  let pos = []
  " The start position of match
  let start = 0
  let line = getline(a:lnum)

  let first_col_str = matchstr(line, s:state.first_column_pattern)
  let first_col = split(first_col_str, '\zs')

  " Try first col full match
  let full_match = match(first_col_str, a:input)
  if full_match > 0
    for start in range(full_match + 1, full_match + len(a:input))
      call add(pos, [a:lnum, start])
    endfor
  endif

  " Try first col
  if start == 0
    let icon_offset = len(first_col_str) - len(first_col)
    for char in search
      let start = index(first_col, char, start, 1) + 1
      if start == 0
        let pos = []
        break
      endif

      call add(pos, [a:lnum, start + icon_offset])
    endfor
  endif

  " No match in first col, try second col
  if start == 0
    let first_length = strlen(first_col_str)
    let second_col_str = matchstr(line, s:state.second_column_pattern)
    let second_col = split(second_col_str, '\zs')
    let second_index = 0
  endif

  " Try second col full match
  if start == 0
    let full_match = match(second_col_str, a:input)
    if full_match > 0
      for start in range(full_match + 1, full_match + len(a:input))
        call add(pos, [a:lnum, start + first_length])
      endfor
    endif
  endif

  " Try second col
  if start == 0
    for char in search
      let start = index(second_col, char, start, 1) + 1
      if start == 0
        break
      endif

      call add(pos, [a:lnum, start + first_length])
      let second_index += 1
    endfor
  endif

  " Try first col following second col
  if start == 0 && second_index > 0
    for char in search[second_index:]
      let start = index(first_col, char, start, 1) + 1

      if start == 0
        break
      endif

      call add(pos, [a:lnum, start])
    endfor
  endif

  return pos
endfunction
