# Add a project, switch between projects, quit
# Title: Projects
Output docs/images/projects.gif
Source docs/demo/common.tape

# A relative path is looked up in project_base
Hide Type ":Say Add a folder as a project, with a note" Enter Show
Sleep 1.8s
Type `:Project inventory "stock service"` Sleep 500ms Enter Sleep 2.2s

Hide Type ":Say Switch projects: move in the list, or type a name, note or path" Enter Show
Sleep 2.2s
Type ":ProjectList" Sleep 300ms Enter Sleep 900ms
Ctrl+K Sleep 500ms Ctrl+K Sleep 500ms Ctrl+K Sleep 600ms Ctrl+J Sleep 800ms
# Matches the note of webshop
Type "online" Sleep 1.5s
Enter Sleep 2s

Hide Type ":Say Quit the project" Enter Show
Sleep 1.5s
Type ":ProjectQuit" Sleep 300ms Enter Sleep 2.2s
