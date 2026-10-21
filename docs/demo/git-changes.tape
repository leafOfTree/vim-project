# Local changes: diff, changelists, shelve and unshelve
# Title: Git changes
Output docs/images/git-changes.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Hide Type ":Say Local changes, with the diff of the file under the cursor" Enter Show
Sleep 1.8s
Type ":ProjectGitStatus" Sleep 300ms Enter Sleep 1.2s
Down Sleep 1.2s
Down Sleep 1.5s

Hide Type ":Say Move cart.js to a changelist of its own" Enter Show
Sleep 1.8s
Type "m" Sleep 500ms Type "cart" Sleep 400ms Enter Sleep 1.5s

# Saved as a patch, then removed
Type "G" Sleep 300ms
Type "?Untracked" Enter Sleep 300ms Enter Sleep 600ms
Down Sleep 400ms
Hide Type ":Say Shelve the new file for later" Enter Show
Sleep 1.8s
Type "s" Sleep 500ms Type "later" Sleep 400ms Enter Sleep 1.8s

Type "?later" Enter Sleep 400ms
Hide Type ":Say Bring it back" Enter Show
Sleep 1.5s
Type "S" Sleep 2s
