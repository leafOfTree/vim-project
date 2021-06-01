function! s:TrimQuote(args)
  let args = a:args
  let args = substitute(args, "^'", '', 'g')
  let args = substitute(args, "'$", '', 'g')
  return args
endfunction

command Project call project#ListProjects()
command ProjectList call project#ListProjects()
command ProjectExit call project#ExitProject()
command ProjectInfo call project#ShowProjectInfo()
command ProjectRoot call project#OpenProjectRoot()
command ProjectConfig call project#OpenProjectConfig()
command ProjectTotalConfig call project#OpenTotalConfig()
command -nargs=? ProjectOutput call project#OutputProjects(<q-args>)
command -complete=customlist,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#OpenProjectByName(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectAdd call project#AddProjectFromUser(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectFromFile call project#AddProjectFromFile(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectBase call project#SetBase(s:TrimQuote(<q-args>))

command -complete=dir -nargs=1
      \ ProjectIgnore call project#IgnoreProject(s:TrimQuote(<q-args>))

call project#begin()
