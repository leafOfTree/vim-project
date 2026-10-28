#!/usr/bin/env bash
# Make a repository that stops on merge conflicts, to try the merge window.
#
#   test/demo_merge.sh                 # merge with two conflicts in f.txt, and
#                                      # a line each side changed alone
#   test/demo_merge.sh rebase          # the same, stopped in a rebase
#   test/demo_merge.sh delete          # they deleted f.txt, you changed it
#   test/demo_merge.sh merge DIR       # in DIR instead of /tmp/merge-demo
#
# Run it again to start over: DIR is removed first.
set -eu

mode="${1:-merge}"
# Not $TMPDIR: on macOS it is a long per-user path under /var/folders
dir="${2:-/tmp/merge-demo}"
plugin="$(cd "$(dirname "$0")/.." && pwd)"

case "$mode" in
  merge|rebase|delete) ;;
  *)
    echo "Unknown mode: $mode (merge, rebase or delete)" >&2
    exit 1
    ;;
esac

echo "==> Making $dir"
rm -rf "$dir"
mkdir -p "$dir"
cd "$dir"
git init -q
git config user.name demo
git config user.email demo@example.com
git checkout -q -b main

printf 'a\nb\nc\nd\ne\nf\ng\nh\n' > f.txt
git add f.txt
git commit -q -m init

git checkout -q -b feature
if [ "$mode" = delete ]; then
  git rm -q f.txt
  git commit -q -m 'feature: delete f.txt'
else
  printf 'a\nB theirs\nc\nD theirs\ne\nF theirs\ng\nh\n' > f.txt
  git commit -q -am 'feature: change b, d and f'
fi

git checkout -q main
printf 'a\nB yours\nc\nD yours\ne\nf\ng\nH yours\n' > f.txt
git commit -q -am 'main: change b, d and h'

cmd=merge
[ "$mode" = rebase ] && cmd=rebase
echo "==> Running git $cmd feature, it stops on conflicts:"
if [ "$cmd" = rebase ]; then
  git rebase feature >/dev/null 2>&1 || true
else
  git merge feature >/dev/null 2>&1 || true
fi
git status --short | sed 's/^/    /'

cat <<EOF

==> Now, in Vim with this plugin (the dev-merge branch) loaded:

    :Project $dir
    :ProjectGitStatus

  :ProjectRemove $(basename "$dir") forgets the project when you are done.

  Or straight into the merge window, without a project:

    cd $dir
    vim -c 'set rtp^=$plugin' -c 'let \$vim_project = getcwd()' -c "call project#git_merge#Open('f.txt')"

==> In the local changes, expand Unmerged and open f.txt (Enter by default,
  "open_changelist_or_file"). In the merge window:

    <  take yours     >  take theirs    =  both    e  edit by hand    u  undo
    ]c / [c  move between conflicts     q  accept, git add     Q  discard choices

  A in the local changes aborts the $cmd. Run this script again to start over.
EOF
