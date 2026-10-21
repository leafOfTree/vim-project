# Find in files, then replace in all listed lines
# Title: Find and replace in files
Output docs/images/find-replace.gif
Source docs/demo/common.tape
Source docs/demo/open-webshop.tape

Hide Type ":Say Rename addToCart to addItem in every file" Enter Show
Sleep 2s
Type ":ProjectFindInFiles" Sleep 300ms Enter Sleep 600ms
Type "addToCart" Sleep 1.8s
Ctrl+R Sleep 600ms
Type "addItem" Sleep 2000ms
Ctrl+Y Sleep 1.5s
Type ":edit src/store/cart.js" Sleep 300ms Enter Sleep 2s
