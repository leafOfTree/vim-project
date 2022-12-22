let upgraded_with_prev_config = project#checkVersion()
if upgraded_with_prev_config
  finish
endif

function! s:TrimQuote(args)
  let args = a:args
  let args = substitute(args, "^'", '', 'g')
  let args = substitute(args, "'$", '', 'g')
  return args
endfunction

command ProjectList call project#ListProjects()
command ProjectQuit call project#QuitProject()
command ProjectConfigReload call project#ReloadProject()
command ProjectInfo call project#ShowProjectInfo()
command ProjectAllInfo call project#ShowProjectAllInfo()
command ProjectRoot call project#OpenProjectRoot()
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
command -nargs=? -range 
      \ ProjectFindInFiles call project#FindInFiles(s:TrimQuote(<q-args>), <q-range>)
command ProjectRun call project#RunTasks()

call project#begin()
