#!/bin/bash
# Run one Antigravity prompt non-interactively, with the traps closed.
#   run-agy.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-e EFFORT] [-C DIR] [-t MINUTES] [--mode plan|accept-edits] [--no-proceed]
# The prompt is attached to --print (a bare argument is swallowed), stdin is closed, a watchdog
# caps the wall clock, and if the run stops at a plan gate ("click Proceed") without a report the
# wrapper continues the conversation once to get the report printed. Falls back to the printed
# output when no report file exists.
set -u
MODEL=gemini-3.8-flash-high; EFFORT=high; DIR="$PWD"; MINUTES=60; MODE=""; PROCEED=1; PROMPT=""; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) PROMPT="$2"; shift 2;;  -o) REPORT="$2"; shift 2;;  -m) MODEL="$2"; shift 2;;
    -e) EFFORT="$2"; shift 2;;  -C) DIR="$2"; shift 2;;     -t) MINUTES="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;  --no-proceed) PROCEED=0; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
[ -n "$PROMPT" ] && [ -n "$REPORT" ] || { echo "usage: run-agy.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-e EFFORT] [-C DIR] [-t MINUTES] [--mode plan|accept-edits] [--no-proceed]" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "no prompt file at $PROMPT" >&2; exit 2; }
AGY=$(command -v agy || echo "$HOME/.local/bin/agy")
# Nesting guard: agents calling agents calling agents burns budget invisibly.
DEPTH=${EXTERNAL_MODELS_DEPTH:-0}
[ "$DEPTH" -ge 2 ] && { echo "refusing: external-models nesting depth $DEPTH; break the loop" >&2; exit 3; }
export EXTERNAL_MODELS_DEPTH=$((DEPTH + 1))
# It runs with permissions skipped and can edit, so never in a main checkout by accident.
if [ "$MODE" != "plan" ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  GD=$(cd "$(git -C "$DIR" rev-parse --git-dir)" && pwd -P); GC=$(cd "$(git -C "$DIR" rev-parse --git-common-dir)" && pwd -P)
  [ "$GD" = "$GC" ] && { echo "refusing: -C $DIR is a repository's main checkout and this run may edit. Use a detached worktree (git worktree add --detach DIR HEAD) or --mode plan." >&2; exit 4; }
fi
mkdir -p "$(dirname "$REPORT")"
STDOUT="$REPORT.stdout"; STDERR="$REPORT.stderr"
MODEFLAG=(); [ -n "$MODE" ] && MODEFLAG=(--mode "$MODE")
# A Gemini model name carries its effort (gemini-3.8-flash-high); passing a different --effort is
# refused as a conflict, so --effort goes only with models whose name carries none.
EFFORTFLAG=(--effort "$EFFORT")
case "$MODEL" in *-high|*-medium|*-low) EFFORTFLAG=(); EFFORT="in the model name";; esac
echo "agy: model=$MODEL effort=$EFFORT mode=${MODE:-default} dir=$DIR cap=${MINUTES}m report=$REPORT"
START=$(date +%s)
cd "$DIR" || exit 2
perl -e 'alarm shift; exec @ARGV' -- $((MINUTES * 60)) "$AGY" --model "$MODEL" ${EFFORTFLAG[@]+"${EFFORTFLAG[@]}"} ${MODEFLAG[@]+"${MODEFLAG[@]}"} \
  --dangerously-skip-permissions --print-timeout "${MINUTES}m" --output-format text \
  --print="$(cat "$PROMPT")" < /dev/null > "$STDOUT" 2> "$STDERR"
CODE=$?
if [ ! -s "$REPORT" ] && [ $PROCEED -eq 1 ] && grep -qi "proceed" "$STDOUT"; then
  echo "stopped at a plan gate; continuing the conversation for the report"
  LEFT=$(( MINUTES * 60 - ( $(date +%s) - START ) )); [ $LEFT -lt 300 ] && LEFT=300
  perl -e 'alarm shift; exec @ARGV' -- $LEFT "$AGY" --continue --model "$MODEL" ${EFFORTFLAG[@]+"${EFFORTFLAG[@]}"} ${MODEFLAG[@]+"${MODEFLAG[@]}"} \
    --dangerously-skip-permissions --print-timeout "$((LEFT / 60 + 1))m" --output-format text \
    --print="Proceed. Do not write any file inside the repository; print the complete final report now, in exactly the format the original prompt specified, in full." \
    < /dev/null > "$STDOUT.2" 2>> "$STDERR"
  CODE=$?
  [ -s "$REPORT" ] || cp "$STDOUT.2" "$REPORT"
fi
[ -s "$REPORT" ] || cp "$STDOUT" "$REPORT"
echo "exit=$CODE after $(( $(date +%s) - START ))s; transcript in $STDOUT (and .2 if continued)"
echo "=== report ($REPORT) ==="; cat "$REPORT"
exit $CODE
