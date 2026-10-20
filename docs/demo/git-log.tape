# Search git log, see the changed files and diffs, merge a branch
# Title: Git log, file history and branches
Output docs/images/git-log.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Type ":ProjectGitLog" Sleep 300ms Enter Sleep 1.5s
Ctrl+K Sleep 900ms Ctrl+K Sleep 900ms
Type "cart" Sleep 1.5s
Ctrl+K Sleep 1200ms
Escape Sleep 500ms
Type ":edit src/store/cart.js" Sleep 300ms Enter Sleep 600ms
Type ":ProjectGitFileHistory" Sleep 300ms Enter Sleep 1.5s
Ctrl+K Sleep 1.5s
Escape Sleep 800ms

# Merge a branch: <C-o> asks first, y merges
Type ":ProjectGitBranch" Sleep 300ms Enter Sleep 1.2s
Type "check" Sleep 800ms
Ctrl+O Sleep 1.8s
Type "y" Sleep 1.5s
# Its commit is now in the log: clear the kept input, select the newest
Type ":ProjectGitLog" Sleep 300ms Enter Sleep 800ms
Ctrl+U Sleep 600ms Ctrl+L Sleep 2.5s
Escape Sleep 500ms
