"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"
" Commands {{{
"
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
command ProjectList call project#main#ListProjects()
command ProjectExit call project#main#ExitProject()
command ProjectInfo call project#main#ShowProjectInfo()
command ProjectHome call project#main#OpenProjectHome()
command ProjectConfig call project#main#OpenProjectConfig()
command -complete=custom,project#ListProjectNames -nargs=1
      \ ProjectOpen call project#main#OpenProjectByName(<args>)
"}}}

" vim: fdm=marker
