#!/usr/bin/env bash
# Run the vim-project regression tests headlessly.
#
#   test/run.sh            # run with every editor found (nvim and vim)
#   test/run.sh nvim       # run with Neovim only
#   test/run.sh vim        # run with Vim only
#
# Exit code is non-zero when any test fails or an editor is missing.
set -u

here="$(cd "$(dirname "$0")" && pwd)"
runner="$here/runner.vim"

# Pick the editors to run. "vim" may be an alias for nvim on some machines,
# so make sure the binary really is Vim before using it.
editors=()
if [ "$#" -gt 0 ]; then
  editors=("$@")
else
  command -v nvim >/dev/null 2>&1 && editors+=(nvim)
  if command -v vim >/dev/null 2>&1 && vim --version 2>/dev/null | head -1 | grep -q '^VIM'; then
    editors+=(vim)
  fi
fi

if [ "${#editors[@]}" -eq 0 ]; then
  echo "No vim or nvim found" >&2
  exit 1
fi

status=0
for editor in "${editors[@]}"; do
  if ! command -v "$editor" >/dev/null 2>&1; then
    echo "==> $editor: not found" >&2
    status=1
    continue
  fi

  output="$(mktemp "${TMPDIR:-/tmp}/vim-project-test.XXXXXX")"
  echo "==> Running tests with $editor"
  case "$editor" in
    nvim)
      VIM_PROJECT_TEST_OUTPUT="$output" \
        nvim --headless -u NONE -i NONE -n -S "$runner" >/dev/null 2>&1
      ;;
    *)
      VIM_PROJECT_TEST_OUTPUT="$output" \
        "$editor" -N -u NONE -i NONE -n -es -S "$runner" >/dev/null 2>&1
      ;;
  esac
  code=$?

  if [ -s "$output" ]; then
    cat "$output"
  else
    echo "No test output was produced (editor exit code $code)"
    code=1
  fi
  rm -f "$output"

  if [ "$code" -ne 0 ]; then
    echo "==> $editor: FAILED (exit $code)"
    status=1
  else
    echo "==> $editor: OK"
  fi
  echo
done

exit $status
