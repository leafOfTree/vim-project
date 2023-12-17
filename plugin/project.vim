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

command ProjectList call project#list_projects#run()
command ProjectQuit call project#QuitProject()
command ProjectConfigReload call project#ReloadProject()
command ProjectInfo call project#ShowProjectInfo()
command ProjectAllInfo call project#ShowProjectAllInfo()
command ProjectRoot call project#OpenProjectRoot()
command ProjectConfig call project#OpenProjectConfig()
command ProjectAllConfig call project#OpenAllConfig()
command -nargs=? ProjectOutput call project#list_projects#OutputProjects(<q-args>)

command -complete=customlist,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#OpenProjectByName(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListAllProjectNames -nargs=1
      \ ProjectRemove call project#RemoveProjectByName(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListAllProjectNames -nargs=+
      \ ProjectRename call project#RenameProjectByName(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListDirs -nargs=+
      \ Project call project#AddProject(s:TrimQuote(<q-args>))

command -complete=customlist,project#ListDirs -nargs=1
      \ ProjectIgnore call project#IgnoreProject(s:TrimQuote(<q-args>))

command ProjectSearchFiles call project#search_files#run()

command -nargs=? -range 
      \ ProjectFindInFiles call project#find_in_files#run(s:TrimQuote(<q-args>), <q-range>)

command ProjectRun call project#run_tasks#run()

command ProjectGitLog call project#git#log()
command -range ProjectGitFileHistory call project#git#file_history(<q-range>)
command ProjectGitCommit call project#git#commit()

call project#begin()
