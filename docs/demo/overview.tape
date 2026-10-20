# Overview: open a project, search files, find in files, lint and fix, git changes
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

# Lint finds a console.log left in the cart, fix it and lint again
Type ":ProjectRun" Sleep 300ms Enter Sleep 800ms
Type "lint" Sleep 500ms Enter Sleep 4s
Escape Sleep 500ms
Type ":ProjectSearchFiles" Sleep 300ms Enter Sleep 600ms
Type "store/c" Sleep 800ms Enter Sleep 900ms
Type "/console" Sleep 300ms Enter Sleep 700ms
Type "dd" Sleep 600ms
Type ":w" Sleep 300ms Enter Sleep 700ms
# The list keeps the input, "lint": Enter runs it again
Type ":ProjectRun" Sleep 300ms Enter Sleep 1s
Enter Sleep 2.2s
Escape Sleep 500ms

Type ":ProjectGitStatus" Sleep 300ms Enter Sleep 1s
# cart.js: console.log removed, clearCart added
Down Sleep 900ms Down Sleep 3.5s
