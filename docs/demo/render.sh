#!/usr/bin/env bash
# Record the README animations with VHS (https://github.com/charmbracelet/vhs)
#
#   docs/demo/render.sh            all tapes
#   docs/demo/render.sh overview   one tape
#
# Each tape starts from a fresh workspace (docs/demo/setup.sh) and writes
# docs/images/<name>.gif. Feature tapes also take a screenshot, which gets a
# play badge (docs/demo/play.png) to become the still poster shown in the
# README. Needs vhs, ffmpeg, nvim, git and fd or find.
set -euo pipefail
cd "$(dirname "$0")/../.."

tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
  tapes=(overview projects search-files find-replace run-tasks git-changes git-log)
fi

for name in "${tapes[@]}"; do
  echo "==> $name"
  # Now and then VHS dithers every frame differently, which makes the GIF
  # hundreds of times bigger (once 118M, over GitHub's 100M limit): record again
  for try in 1 2 3; do
    docs/demo/setup.sh >/dev/null
    vhs "docs/demo/$name.tape" >/dev/null 2>&1
    size=$(wc -c < "docs/images/$name.gif")
    [ "$size" -le $((3 * 1024 * 1024)) ] && break
    echo "    $((size / 1024 / 1024))M is too big, recording again"
    if [ "$try" -eq 3 ]; then
      echo "    giving up on $name" >&2
      exit 1
    fi
  done
  poster="docs/images/$name.png"
  if [ -f "$poster" ]; then
    ffmpeg -loglevel error -y -i "$poster" -i docs/demo/play.png \
      -filter_complex 'overlay=(W-w)/2:(H-h)/2' "$poster.tmp.png"
    mv "$poster.tmp.png" "$poster"
  fi
  ls -lh "docs/images/$name".* | awk '{print "    " $5 "  " $9}'
done
