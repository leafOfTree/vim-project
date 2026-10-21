# Where the projects are, add two, then switch between projects
# Title: Projects
Output docs/images/projects.gif

# The shell shows where it is; nvim starts with the demo config
Hide
Type `export VIM_PROJECT_DEMO=/tmp/vim-project-demo && cd $VIM_PROJECT_DEMO/projects && alias nvim="nvim -u $OLDPWD/docs/demo/vimrc" && PS1='\w $ ' && clear`
Enter
Show
Sleep 800ms
Type "ls -F" Sleep 400ms Enter Sleep 2.2s
Type "nvim" Sleep 400ms Enter Sleep 1.5s

Hide Type ":Say Add a project by its absolute path, from anywhere" Enter Show
Sleep 1.8s
Type ":Project /tmp/vim-project-demo/work/admin" Sleep 500ms Enter Sleep 2s

# A relative path is looked up in project_base
Hide Type ":Say Or by a path relative to project_base, with a note" Enter Show
Sleep 1.8s
Type `:Project inventory "stock service"` Sleep 500ms Enter Sleep 2s

Hide Type ":Say Switch projects: move in the list, or type a name, note or path" Enter Show
Sleep 2.2s
Type ":ProjectList" Sleep 300ms Enter Sleep 900ms
Ctrl+K Sleep 500ms Ctrl+K Sleep 500ms Ctrl+K Sleep 600ms Ctrl+J Sleep 800ms
# Matches the note of webshop
Type "online" Sleep 1.5s
Enter Sleep 2s

# Characters in order: blg finds blog
Type ":ProjectList" Sleep 300ms Enter Sleep 700ms
Type "blg" Sleep 1s Enter Sleep 2.5s
