# Look into the cart's history and how a function changed, merge a branch
# Title: Git log, file history and branches
Output docs/images/git-log.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

# Search the log, then open a commit to see the diff of each file
Hide Type ":Say What changed in the cart lately?" Enter Show
Sleep 1.8s
Type ":ProjectGitLog" Sleep 300ms Enter Sleep 900ms
Type "cart" Sleep 1.5s
Ctrl+K Sleep 1.5s
Ctrl+K Sleep 1.5s
# Open the commit: its files, with the diff of the one under the cursor
Enter Sleep 2s
Down Sleep 1.8s
Down Sleep 2.5s
Type ":only" Sleep 300ms Enter Sleep 400ms

# History of the selected lines: each commit that changed them, with its diff
Type ":edit src/store/cart.js" Sleep 300ms Enter
Type "3G" Sleep 300ms
Hide Type ":Say How did addToCart change?" Enter Show
Sleep 1.8s
Type "V" Sleep 300ms Type "4j" Sleep 600ms
Type ":ProjectGitFileHistory" Sleep 300ms Enter Sleep 2.5s
Ctrl+K Sleep 2.2s
Ctrl+K Sleep 2.5s
Escape Sleep 400ms

# Merge a branch: <C-o> asks first, then its commit is in the log
Hide Type ":Say Merge the checkout branch" Enter Show
Sleep 1.5s
Type ":ProjectGitBranch" Sleep 300ms Enter Sleep 900ms
Type "check" Sleep 800ms
Ctrl+O Sleep 1.5s
Type "y" Sleep 1.2s
Type ":ProjectGitLog" Sleep 300ms Enter Sleep 600ms
Ctrl+U Sleep 500ms Ctrl+L Sleep 1.5s
# Open it to see what the branch brought
Enter Sleep 3.5s
