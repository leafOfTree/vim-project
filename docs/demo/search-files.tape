# Search files by name: fuzzy, by path, directories, open in a split
# Title: Search files
Output docs/images/search-files.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Hide Type ":Say Find files by name, by path with /, or folders ending with /" Enter Show
Sleep 2.2s
Type ":ProjectSearchFiles" Sleep 300ms Enter Sleep 1s
Type "pcard" Sleep 1.2s
Ctrl+U Sleep 300ms
Type "store/c" Sleep 1200ms
Ctrl+U Sleep 300ms
Type "comp/" Sleep 1.2s
Ctrl+U Sleep 300ms
Type "cbtn" Sleep 1s
Ctrl+V Sleep 1s
Hide Type ":Say Ctrl-v opened it in a vertical split" Enter Show
Sleep 2s
