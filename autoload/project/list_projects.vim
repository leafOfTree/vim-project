function! project#list_projects#run()
  call project#PrepareListBuffer('Open a project:', 'PROJECTS')
  let Init = function('s:Init')
  let Update = function('s:Update')
  let Open = function('s:Open')
  call project#RenderList(Init, Update, Open)
endfunction

function! project#list_projects#OutputProjects(...)
  let filter = a:0>0 ? a:1 : ''
  let projects = project#GetVariable('projects')
  let projects = s:FilterProjects(projects, filter)
  echo projects
endfunction

function! s:Init(input)
  let projects = project#GetVariable('projects')
  let max_col_width = project#GetVariable('max_width') / 3 - 3
  call project#Tabulate(projects, ['name', 'path', 'note'], 0, max_col_width)
  call s:Update(a:input)
endfunction

function! s:Update(input)
  let projects = project#GetVariable('projects')
  let list = s:FilterProjects(copy(projects), a:input)
  let display = s:GetProjectsDisplay(list)
  call project#SetVariable('list', list)
  call project#ShowInListBuffer(display, a:input)
  call project#HighlightCurrentLine(len(display))
  call project#HighlightInputChars(a:input)
  call project#HighlightNoResults()
endfunction

function! s:Open(project, open_cmd, input)
  if s:IsValidProject(a:project)
    call project#OpenProject(a:project)
  else
    call project#Warn('Not accessible path: '.a:project.fullpath)
  endif
endfunction

function! s:IsValidProject(project)
  let fullpath = a:project.fullpath
  return isdirectory(fullpath) || filereadable(fullpath)
endfunction

function! s:GetProjectsDisplay(list)
  return map(copy(a:list), function('s:GetProjectsDisplayRow'))
endfunction

function! s:GetProjectsDisplayRow(key, value)
  let value = a:value
  return value.__name.'  '
        \.value.__note.'  '
        \.project#ReplaceHomeWithTide(value.__path)
endfunction

function! s:FilterProjects(projects, filter)
  let projects = a:projects
  call s:FilterProjectsByView(projects)
  call s:RemoveCurrentProject(projects)

  if a:filter == ''
    call sort(projects, 's:SortInitialProjectsList')
  else
    let projects = s:FilterProjectsList(projects, a:filter)
  endif

  return projects
endfunction

function! s:RemoveCurrentProject(projects)
  let project = project#GetVariable('project')
  if empty(project)
    return
  endif
  call filter(a:projects, {_, value -> value.fullpath != project.fullpath})
endfunction

function! s:SortInitialProjectsList(a1, a2)
  let project_history = project#GetVariable('project_history')
  let index1 = index(project_history, a:a1.fullpath)
  let index2 = index(project_history, a:a2.fullpath)
  if index1 == -1 && index2 == -1
    return a:a1.name < a:a2.name ? 1 : -1
  elseif index1 == -1
    return -1
  elseif index2 == -1
    return 1
  else
    return index2 - index1
  endif
endfunction

function! s:FilterProjectsByView(projects)
  let project_views = project#GetVariable('project_views')
  let view_index = project#GetVariable('view_index')
  let max = len(project_views)
  if view_index >= 0 && view_index < max
    let view = project_views[view_index]
    if len(view) == 2
      let [show, hide] = view
    elseif len(view) == 1
      let show = view[0]
      let hide = ''
    else
      let show = ''
      let hide = ''
    endif
    call s:FilterProjectsListName(a:projects, show, 0)
    call s:FilterProjectsListName(a:projects, hide, 1)
  endif
endfunction

function! s:FilterProjectsListName(list, filter, reverse)
  let list = a:list
  let filter = a:filter
  call filter(list, { _, value -> empty(filter) ||
        \(!a:reverse  ? value.name =~ filter : value.name !~ filter)
        \})
  return list
endfunction

function! s:FilterProjectsList(list, filter)
  let regexp_filter = join(split(a:filter, '\zs'), '.*')

  for item in a:list
    let item._match_type = ''
    let item._match_index = -1

    " Filter by name
    let match_index = match(item.name, regexp_filter)
    if match_index != -1
      " Prefer exact match. If not, add 10 to match_index
      if len(a:filter) > 1 && count(tolower(item.name), a:filter) == 0
        let match_index = match_index + 10
      endif

      let item._match_type = 'name'
      let item._match_index = match_index
    endif

    " Filter by note
    if match_index == -1
      if has_key(item.option, 'note')
        let match_index = match(item.option.note, regexp_filter)
        if match_index != -1
          let item._match_type = 'note'
          let item._match_index = match_index
        endif
      endif
    endif

    " Filter by path
    if match_index == -1
      let path = project#ReplaceHomeWithTide(item.path)
      let match_index = match(path, regexp_filter)
      if match_index != -1
        let item._match_type = 'path'
        let item._match_index = match_index
      endif
    endif

    " Filter by path+name
    if match_index == -1
      let full_path = project#ReplaceHomeWithTide(item.path.item.name)
      let match_index = match(full_path, regexp_filter)
      if match_index != -1
        let item._match_type = 'full_path'
        let item._match_index = match_index
      endif
    endif
  endfor

  " Try matching name and note. If none, then match path, etc.
  let result = filter(copy(a:list), { _, val -> val._match_type == 'name' || val._match_type == 'note' })
  if len(result) == 0
    let result = filter(a:list, { _, val -> val._match_type != '' })
  endif
  call sort(result, 's:SortProjectsList')
  return result
endfunction

function! s:SortProjectsList(a1, a2)
  let type1 = a:a1._match_type
  let type2 = a:a2._match_type
  let index1 = a:a1._match_index
  let index2 = a:a2._match_index

  " name > full_path > note > path
  if type1 == 'name' && type2 != 'name'
    return 1
  endif
  if type1 == 'full_path' && type2 != 'name' && type2 != 'full_path'
    return 1
  endif
  if type1 == 'note' && type2 == 'path'
    return 1
  endif
  if type1 == type2
    if index1 == index2
      return len(a:a2.name) - len(a:a1.name)
    else
      return index2 - index1
    endif
  endif
  return -1
endfunction
