#!/bin/bash
# Run one Codex prompt non-interactively, with the traps closed.
#   run-codex.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-e EFFORT] [-C DIR] [-s SANDBOX] [-t MINUTES]
# stdin is closed (Codex blocks on an open pipe), a watchdog caps the wall clock, stdout and
# stderr are saved beside the report, and the report (Codex's final message) is printed at the end.
set -u
MODEL=gpt-6-astra; EFFORT=high; DIR="$PWD"; SANDBOX=read-only; MINUTES=90; PROMPT=""; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) PROMPT="$2"; shift 2;;  -o) REPORT="$2"; shift 2;;  -m) MODEL="$2"; shift 2;;
    -e) EFFORT="$2"; shift 2;;  -C) DIR="$2"; shift 2;;     -s) SANDBOX="$2"; shift 2;;
    -t) MINUTES="$2"; shift 2;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
[ -n "$PROMPT" ] && [ -n "$REPORT" ] || { echo "usage: run-codex.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-e EFFORT] [-C DIR] [-s SANDBOX] [-t MINUTES]" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "no prompt file at $PROMPT" >&2; exit 2; }
CODEX=$(command -v codex || echo "$HOME/.local/bin/codex")
# Nesting guard: agents calling agents calling agents burns budget invisibly.
DEPTH=${EXTERNAL_AGENTS_DEPTH:-0}
[ "$DEPTH" -ge 2 ] && { echo "refusing: external-agents nesting depth $DEPTH; break the loop" >&2; exit 3; }
export EXTERNAL_AGENTS_DEPTH=$((DEPTH + 1))
# A sandbox that can write must not run in a main checkout by accident.
if [ "$SANDBOX" != "read-only" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  GD=$(cd "$(git -C "$DIR" rev-parse --git-dir)" && pwd -P); GC=$(cd "$(git -C "$DIR" rev-parse --git-common-dir)" && pwd -P)
  [ "$GD" = "$GC" ] && { echo "refusing: -C $DIR is a repository's main checkout and -s $SANDBOX can write. Use a detached worktree, or -s read-only." >&2; exit 4; }
fi
mkdir -p "$(dirname "$REPORT")"
STDOUT="$REPORT.stdout"; STDERR="$REPORT.stderr"
if pgrep -f "codex exec" >/dev/null; then echo "note: another 'codex exec' is running (pgrep -f 'codex exec'); continuing" >&2; fi
echo "codex exec: model=$MODEL effort=$EFFORT sandbox=$SANDBOX dir=$DIR cap=${MINUTES}m report=$REPORT"
START=$(date +%s)
perl -e 'alarm shift; exec @ARGV' -- $((MINUTES * 60)) "$CODEX" exec -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" \
  -s "$SANDBOX" -C "$DIR" -o "$REPORT" "$(cat "$PROMPT")" < /dev/null > "$STDOUT" 2> "$STDERR"
CODE=$?
echo "exit=$CODE after $(( $(date +%s) - START ))s; transcript in $STDERR"
if [ -s "$REPORT" ]; then
  echo "=== report ($REPORT) ==="; cat "$REPORT"
else
  echo "=== no report was written; last lines of stderr ==="; tail -n 20 "$STDERR"
  echo "(a usage limit says 'try again at ...'; a watchdog kill is exit 142 or 137)"
fi
exit $CODE
