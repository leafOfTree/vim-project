#!/usr/bin/env bash
# Record the README animations with VHS (https://github.com/charmbracelet/vhs)
#
#   docs/demo/render.sh            all tapes
#   docs/demo/render.sh overview   one tape
#
# Each tape starts from a fresh workspace (docs/demo/setup.sh) and writes
# docs/images/<name>.gif. Needs vhs, nvim, git and fd or find.
set -euo pipefail
cd "$(dirname "$0")/../.."

tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
  tapes=(overview projects search-files find-replace run-tasks git-changes git-log)
fi

for name in "${tapes[@]}"; do
  echo "==> $name"
  docs/demo/setup.sh >/dev/null
  vhs "docs/demo/$name.tape" >/dev/null
  ls -lh "docs/images/$name.gif" | awk '{print "    " $5 "  " $9}'
done
