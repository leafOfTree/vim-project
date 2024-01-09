function! project#new#NewProject()
  let prompt = 'Generate new project by:' 
  call project#PrepareListBuffer(prompt, 'GIT_FILE_HISTORY')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! s:Init(input)
  let s:list = [
        \ { 'name': 'vite', 'cmd': 'npm craete vite@latest' },
        \ { 'name': 'spring', 'cmd': 'spring' },
        \ { 'name': 'git', 'cmd': 'git clone --depth 1' },
        \ { 'name': 'degit', 'cmd': 'degit' },
        \]

  let max_col_width = project#GetVariable('max_width') / 2 - 10
  call project#Tabulate(s:list, ['name', 'cmd'])

  call s:Update(a:input)
endfunction

function! s:Update(input)
  let show_list = s:FilterGenerator(copy(s:list), a:input)
  let display = s:GetNewProjectGeneratorDisplay(show_list)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
endfunction

function! s:Open(item, open_cmd, input)
endfunction

function! s:GetNewProjectGeneratorDisplay(list)
  let display = []
  for generator in a:list
    let row = generator.__name.'  '.generator.__cmd
    call add(display, row)
  endfor

  return display
endfunction

function! s:FilterGenerator(generators, input)
  let regexp_input = join(split(a:input, '\zs'), '.*')
  for item in a:generators
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

  let result = filter(a:generators, { _, val -> val._match_type != '' })
  return result
endfunction

