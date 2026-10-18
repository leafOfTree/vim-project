let s:view_index = 0
" Display row of each project, by fullpath
let s:rows = {}

function! project#list_projects#Run()
  call project#list#Open({
        \'type': 'PROJECTS',
        \'prompt': 'Open a project:',
        \'mappings': project#config#Get('list_mappings_projects'),
        \'Init': function('s:Init'),
        \'Update': function('s:Update'),
        \'Open': function('s:Open'),
        \'handlers': {
        \  'next_view': function('s:NextView'),
        \  'prev_view': function('s:PrevView'),
        \},
        \})
endfunction

function! project#list_projects#OutputProjects(...)
  let filter = a:0>0 ? a:1 : ''
  let projects = s:FilterProjects(copy(project#GetProjects()), filter)
  echo projects
endfunction

function! s:Init(input)
  let projects = project#GetProjects()
  let max_col_width = project#list#State().max_width / 3 - 3
  let columns = project#list#Tabulate(projects, ['name', 'path', 'note'], 0, max_col_width)

  let s:rows = {}
  for idx in range(len(projects))
    let column = columns[idx]
    let s:rows[projects[idx].fullpath] = column.name.'  '.column.note.'  '.column.path
  endfor

  call s:Update(a:input)
endfunction

function! s:Update(input)
  let list = s:FilterProjects(copy(project#GetProjects()), a:input)
  let display = map(copy(list), {_, project -> s:rows[project.fullpath]})

  let state = project#list#State()
  let state.list = list
  call project#list#Show(display, a:input)
  call project#list#HighlightCurrentLine(len(display))
  call project#list#HighlightInputChars(a:input)
  call project#list#HighlightNoResults()
endfunction

function! s:Open(project, open_cmd, input)
  if s:IsValidProject(a:project)
    call project#OpenProject(a:project)
  else
    call project#Warn('Not accessible path: '.a:project.fullpath)
  endif
endfunction

function! s:NextView(state)
  let max = len(project#config#Get('project_views'))
  let s:view_index = s:view_index < max - 1 ? s:view_index + 1 : 0
endfunction

function! s:PrevView(state)
  let max = len(project#config#Get('project_views'))
  let s:view_index = s:view_index > 0 ? s:view_index - 1 : max - 1
endfunction

function! s:IsValidProject(project)
  let fullpath = a:project.fullpath
  return isdirectory(fullpath) || filereadable(fullpath)
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
  let project = project#GetCurrentProject()
  if empty(project)
    return
  endif
  call filter(a:projects, {_, value -> value.fullpath != project.fullpath})
endfunction

function! s:SortInitialProjectsList(a1, a2)
  let project_history = project#GetProjectHistory()
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
  let project_views = project#config#Get('project_views')
  let max = len(project_views)
  if s:view_index >= 0 && s:view_index < max
    let view = project_views[s:view_index]
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
