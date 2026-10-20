# Overview: open a project, search files, find in files, git changes
# Title: Projects for Vim and Neovim
Output docs/images/overview.gif
Source docs/demo/common.tape

Type ":ProjectList" Sleep 300ms Enter Sleep 900ms
Type "shop" Sleep 700ms Enter Sleep 1.5s

Type ":ProjectSearchFiles" Sleep 300ms Enter Sleep 900ms
Type "pcard" Sleep 900ms Enter Sleep 1.5s

Type ":ProjectFindInFiles" Sleep 300ms Enter Sleep 600ms
Type "addToCart" Sleep 2s
Ctrl+J Sleep 400ms Ctrl+J Sleep 600ms Enter Sleep 1.5s

Type ":ProjectGitStatus" Sleep 300ms Enter Sleep 1s
Down Sleep 900ms Down Sleep 1.5s
