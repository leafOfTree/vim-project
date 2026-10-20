# Local changes: diff, changelists, shelve and unshelve
Output docs/images/git-changes.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Type ":ProjectGitStatus" Sleep 300ms Enter Sleep 1.2s
Down Sleep 1.2s
Down Sleep 1.2s
# Move cart.js to a new changelist
Type "m" Sleep 500ms Type "cart" Sleep 400ms Enter Sleep 1.5s
# Shelve the untracked file: saved as a patch, then removed
Type "G" Sleep 300ms
Type "?Untracked" Enter Sleep 300ms Enter Sleep 900ms
Down Sleep 800ms
Type "s" Sleep 500ms Type "later" Sleep 400ms Enter Sleep 1.8s
# Unshelve it again
Type "?later" Enter Sleep 600ms
Type "S" Sleep 2s
