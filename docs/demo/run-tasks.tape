# Run tasks and watch their output in the list
# Title: Run tasks
Output docs/images/run-tasks.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Hide Type ":Say Run the tests, then start the dev server and stop it" Enter Show
Sleep 2s
Type ":ProjectRun" Sleep 300ms Enter Sleep 1s
Type "te" Sleep 600ms Enter Sleep 3000ms
Ctrl+U Sleep 300ms
Type "dev" Sleep 600ms Enter Sleep 2.5s
# Ctrl-q stops it
Ctrl+Q Sleep 2s
Escape Sleep 1s
