command ProjectList call project#main#ListProjects()
command -nargs=? ProjectOutput call project#main#OutputProjects(<args>)
command ProjectExit call project#main#ExitProject()
command ProjectInfo call project#main#ShowProjectInfo()
command ProjectRoot call project#main#OpenProjectRoot()
command ProjectConfig call project#main#OpenProjectConfig()
command ProjectPluginConfig call project#main#OpenPluginConfig()
command -complete=custom,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#main#OpenProjectByName(<args>)
