#!/bin/bash
# Package a diff for an external reviewer and give each reviewer its own detached worktree.
#   review-package.sh BASE HEAD OUTDIR [--exclude PATHSPEC]... [--worktree NAME]...
# Writes OUTDIR/commits.txt, diffstat.txt, diff.patch (8 lines of context, excludes applied) and
# OUTDIR/wt-NAME per --worktree, detached at HEAD. Run from inside the repository.
set -eu
[ $# -ge 3 ] || { echo "usage: review-package.sh BASE HEAD OUTDIR [--exclude PATHSPEC]... [--worktree NAME]..." >&2; exit 2; }
BASE="$1"; HEAD="$2"; OUT="$3"; shift 3
EXCLUDES=(); NAMES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude) EXCLUDES+=(":!$2"); shift 2;;
    --worktree) NAMES+=("$2"); shift 2;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
mkdir -p "$OUT/scratch"
git log --oneline "$BASE..$HEAD" > "$OUT/commits.txt"
git diff --stat "$BASE..$HEAD" > "$OUT/diffstat.txt"
git diff -U8 "$BASE..$HEAD" -- . ${EXCLUDES[@]+"${EXCLUDES[@]}"} > "$OUT/diff.patch"
for NAME in ${NAMES[@]+"${NAMES[@]}"}; do
  git worktree add --detach "$OUT/wt-$NAME" "$HEAD" >/dev/null 2>&1
done
echo "package: $(wc -l < "$OUT/commits.txt") commits, $(wc -l < "$OUT/diff.patch") patch lines -> $OUT"
if [ ${#NAMES[@]} -gt 0 ]; then echo "worktrees: $(printf '%s ' "${NAMES[@]/#/$OUT/wt-}")"; fi
echo "remove with: git worktree remove --force $OUT/wt-NAME && git worktree prune"
