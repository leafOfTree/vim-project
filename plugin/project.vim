function! s:TrimQuote(args)
  let args = a:args
  let args = substitute(args, "^'", '', 'g')
  let args = substitute(args, "'$", '', 'g')
  return args
endfunction

command ProjectList call project#ListProjects()
command ProjectQuit call project#QuitProject()
command ProjectInfo call project#ShowProjectInfo()
command ProjectEntry call project#OpenProjectEntry()
command ProjectConfig call project#OpenProjectConfig()
command ProjectTotalConfig call project#OpenTotalConfig()
command -nargs=? ProjectOutput call project#OutputProjects(<q-args>)
command -complete=customlist,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#OpenProjectByName(s:TrimQuote(<q-args>))
command -complete=customlist,project#ListProjectNames -nargs=1
      \ ProjectRemove call project#RemoveProjectByName(s:TrimQuote(<q-args>))

command -complete=dir -nargs=+
      \ Project call project#AddProject(s:TrimQuote(<q-args>))
command -complete=dir -nargs=+
      \ ProjectAdd call project#AddProject(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectBase call project#SetBase(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectIgnore call project#IgnoreProject(s:TrimQuote(<q-args>))

call project#begin()
