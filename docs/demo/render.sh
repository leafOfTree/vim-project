#!/usr/bin/env bash
# Record the README animations with VHS (https://github.com/charmbracelet/vhs)
#
#   docs/demo/render.sh            all tapes
#   docs/demo/render.sh overview   one tape
#
# Each tape starts from a fresh workspace (docs/demo/setup.sh) and writes
# docs/images/<name>.gif, starting with a title card made from title.svg and
# the "# Title:" of the tape. Needs vhs, ffmpeg, rsvg-convert, gifsicle,
# python3, nvim, git and fd or find.
set -euo pipefail
cd "$(dirname "$0")/../.."

tapes=("$@")
if [ ${#tapes[@]} -eq 0 ]; then
  tapes=(overview projects search-files find-replace run-tasks git-changes git-log)
fi

tape="$(mktemp "${TMPDIR:-/tmp}/vim-project-demo.XXXXXX")"
card="$(mktemp "${TMPDIR:-/tmp}/vim-project-card.XXXXXX")"
trap 'rm -f "$tape" "$card" "$card".*' EXIT

# The size of the recordings, which the title card is scaled to
width=$(sed -n 's/^Set Width //p' docs/demo/settings.tape)
height=$(sed -n 's/^Set Height //p' docs/demo/settings.tape)

# title.svg (1200x720) with $1 as title, moved right by $2, written to
# $card.png, scaled to width x height when $3 is given
render_card() {
  sed -e "s/TITLE/$1/" -e "s/OFFSET/$2/" docs/demo/title.svg |
    rsvg-convert ${3:+-w "$width" -h "$height"} -o "$card.png"
}

# $card.gif: the title card fading in and out, 2.1 seconds
make_card() {
  # Render once to find the columns with content, then again centered
  # and at the size of the recordings
  render_card "$1" 0
  local left right
  read -r left right < <(ffmpeg -loglevel error -i "$card.png" -f rawvideo -pix_fmt gray - |
    python3 -c '
import sys
w = 1200
px = sys.stdin.buffer.read()
cols = [x for x in range(w) if any(abs(px[y * w + x] - px[0]) > 16 for y in range(0, len(px) // w, 2))]
print(cols[0], cols[-1])')
  render_card "$1" $(( (1200 - (right - left + 1)) / 2 - left )) scaled
  # Few flat colors: without dithering the card stays small
  ffmpeg -loglevel error -y -loop 1 -framerate 25 -t 2.1 -i "$card.png" -vf \
    'fade=in:d=0.4:color=0x1e1e2e,fade=out:st=1.7:d=0.4:color=0x1e1e2e,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=none' \
    "$card.gif"
  gifsicle -O2 --batch "$card.gif"
}

for name in "${tapes[@]}"; do
  echo "==> $name"
  # Now and then VHS dithers every frame differently, which makes the GIF
  # hundreds of times bigger (once 118M, over GitHub's 100M limit): record again
  for try in 1 2 3; do
    docs/demo/setup.sh >/dev/null
    # settings.tape goes right after Output: VHS applies Set only at the top
    { grep '^Output' "docs/demo/$name.tape"
      cat docs/demo/settings.tape
      grep -v '^Output' "docs/demo/$name.tape"
    } > "$tape"
    vhs "$tape" >/dev/null 2>&1
    size=$(wc -c < "docs/images/$name.gif")
    [ "$size" -le $((3 * 1024 * 1024)) ] && break
    echo "    $((size / 1024 / 1024))M is too big, recording again"
    if [ "$try" -eq 3 ]; then
      echo "    giving up on $name" >&2
      exit 1
    fi
  done
  # Start with a title card, so a reader sees where the loop begins
  make_card "$(sed -n 's/^# Title: //p' "docs/demo/$name.tape")"
  gifsicle --no-warnings --loopcount=forever "$card.gif" \
    "docs/images/$name.gif" -o "$card.out.gif"
  mv "$card.out.gif" "docs/images/$name.gif"
  ls -lh "docs/images/$name.gif" | awk '{print "    " $5 "  " $9}'
done
