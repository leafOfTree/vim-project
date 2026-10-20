# Search git log, see the changed files and diffs
# Title: Git log and file history
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
