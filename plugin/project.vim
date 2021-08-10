function! s:TrimQuote(args)
  let args = a:args
  let args = substitute(args, "^'", '', 'g')
  let args = substitute(args, "'$", '', 'g')
  return args
endfunction

command ProjectList call project#ListProjects()
command ProjectQuit call project#QuitProject()
command ProjectReload call project#ReloadProject()
command ProjectInfo call project#ShowProjectInfo()
command ProjectEntry call project#OpenProjectEntry()
command ProjectConfig call project#OpenProjectConfig()
command ProjectAllConfig call project#OpenAllConfig()
command -nargs=? ProjectOutput call project#OutputProjects(<q-args>)
command -complete=customlist,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#OpenProjectByName(s:TrimQuote(<q-args>))
command -complete=customlist,project#ListAllProjectNames -nargs=1
      \ ProjectRemove call project#RemoveProjectByName(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListDirs -nargs=+
      \ Project call project#AddProject(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListDirs -nargs=1
      \ ProjectIgnore call project#IgnoreProject(s:TrimQuote(<q-args>))

command ProjectSearchFiles call project#SearchFiles()
command ProjectFindInFiles call project#FindInFiles()

call project#begin()
