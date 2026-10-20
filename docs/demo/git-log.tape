# Look into the cart's history, find who added a line, merge a branch
# Title: Git log, file history and branches
Output docs/images/git-log.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

# Search the log: the changed files of each commit show on the right
Hide Type ":Say What changed in the cart lately?" Enter Show
Sleep 1.8s
Type ":ProjectGitLog" Sleep 300ms Enter Sleep 900ms
Type "cart" Sleep 1.5s
Ctrl+K Sleep 1.5s
Ctrl+K Sleep 1.8s
Escape Sleep 400ms

# History of the selected line: the commit that added it, with its diff
Type ":edit src/store/cart.js" Sleep 300ms Enter
Type "5G" Sleep 300ms
Hide Type ":Say Who added this console.log?" Enter Show
Sleep 1.8s
Type "V" Sleep 500ms
Type ":ProjectGitFileHistory" Sleep 300ms Enter Sleep 3.5s
Escape Sleep 400ms

# Merge a branch: <C-o> asks first, then its commit is in the log
Hide Type ":Say Merge the checkout branch" Enter Show
Sleep 1.5s
Type ":ProjectGitBranch" Sleep 300ms Enter Sleep 900ms
Type "check" Sleep 800ms
Ctrl+O Sleep 1.5s
Type "y" Sleep 1.2s
Type ":ProjectGitLog" Sleep 300ms Enter Sleep 600ms
Ctrl+U Sleep 500ms Ctrl+L Sleep 2.5s
Escape Sleep 500ms
