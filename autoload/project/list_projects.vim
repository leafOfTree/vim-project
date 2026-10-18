function! project#list_projects#Run()
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

" Try matching name and note. If none, then match path, etc.
function! s:FilterProjectsList(list, filter)
  let fields = [
        \'name',
        \{ 'type': 'note', 'Get': {item -> get(item.option, 'note', v:null)} },
        \{ 'type': 'path', 'Get': {item -> project#ReplaceHomeWithTide(item.path)} },
        \{ 'type': 'full_path', 'Get': {item -> project#ReplaceHomeWithTide(item.path.item.name)} },
        \]
  return project#util#FuzzyScore(a:list, a:filter, fields, {
        \'priority': ['name', 'full_path', 'note', 'path'],
        \'prefer': ['name', 'note'],
        \'tiebreak': 'name',
        \})
endfunction
