# Shared settings, sourced by every tape
Set Shell "bash"
Set FontSize 16
Set Width 1400
Set Height 640
Set Padding 16
Set Framerate 24
Set PlaybackSpeed 1.4
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

Hide
Type "export VIM_PROJECT_DEMO=/tmp/vim-project-demo PS1='' && cd $VIM_PROJECT_DEMO/projects && clear"
Enter
Type "nvim -u $OLDPWD/docs/demo/vimrc"
Enter
Sleep 1s
Show
