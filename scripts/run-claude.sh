#!/bin/bash
# Run one Claude Code prompt non-interactively, from any agent or shell.
#   run-claude.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-C DIR] [-t MINUTES] [-P MODE] [-S SETTINGS] [--allow-main]
# Calls the binary directly, so the zsh `claude` function's --settings profile (which can route
# the CLI to another provider) does not apply: this is genuine Claude. Pass -S FILE for a profile.
# Models: opus, sonnet, haiku, fable, or a full name. Default opus.
set -u
CLAUDE=$(command -v claude || echo "$HOME/.local/bin/claude")
MODEL=opus; DIR="$PWD"; MINUTES=60; MODE=bypassPermissions; SETTINGS=""; ALLOW_MAIN=0; PROMPT=""; REPORT=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) PROMPT="$2"; shift 2;;  -o) REPORT="$2"; shift 2;;  -m) MODEL="$2"; shift 2;;
    -C) DIR="$2"; shift 2;;     -t) MINUTES="$2"; shift 2;;  -P) MODE="$2"; shift 2;;
    -S) SETTINGS="$2"; shift 2;;  --allow-main) ALLOW_MAIN=1; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
[ -n "$PROMPT" ] && [ -n "$REPORT" ] || { echo "usage: run-claude.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-C DIR] [-t MINUTES] [-P MODE] [-S SETTINGS] [--allow-main]" >&2; exit 2; }
[ -f "$PROMPT" ] || { echo "no prompt file at $PROMPT" >&2; exit 2; }
[ -x "$CLAUDE" ] || { echo "no claude binary at $CLAUDE" >&2; exit 2; }
# Nesting guard: agents calling agents calling agents burns budget invisibly.
DEPTH=${EXTERNAL_MODELS_DEPTH:-0}
[ "$DEPTH" -ge 2 ] && { echo "refusing: external-models nesting depth $DEPTH; break the loop" >&2; exit 3; }
export EXTERNAL_MODELS_DEPTH=$((DEPTH + 1))
# A mode that can edit must not run in a main checkout by accident: use a detached worktree.
if [ "$MODE" != "plan" ] && [ $ALLOW_MAIN -eq 0 ] && git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
  GD=$(cd "$(git -C "$DIR" rev-parse --git-dir)" && pwd -P); GC=$(cd "$(git -C "$DIR" rev-parse --git-common-dir)" && pwd -P)
  [ "$GD" = "$GC" ] && { echo "refusing: -C $DIR is a repository's main checkout and -P $MODE can edit. Use a detached worktree (git worktree add --detach DIR HEAD), -P plan, or --allow-main." >&2; exit 4; }
fi
mkdir -p "$(dirname "$REPORT")"
STDERR="$REPORT.stderr"
SETTINGSFLAG=(); [ -n "$SETTINGS" ] && SETTINGSFLAG=(--settings "$SETTINGS")
echo "claude -p: model=$MODEL permission-mode=$MODE dir=$DIR cap=${MINUTES}m report=$REPORT"
START=$(date +%s)
# A child must not inherit the caller's host-session variables: they name another session's
# socket, token and base URL, and the CLI is not that session. Scrubbed, it authenticates the
# ordinary way -- its own login, an ANTHROPIC_API_KEY, or the profile given with -S.
( cd "$DIR" && env -u ANTHROPIC_BASE_URL -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_SESSION_ID \
      -u CLAUDE_CODE_HOST_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SDK_HAS_OAUTH_REFRESH -u CLAUDE_CODE_SDK_HAS_HOST_AUTH_REFRESH \
      -u CLAUDE_CODE_EXECPATH -u CLAUDE_AGENT_SDK_VERSION \
    perl -e 'alarm shift; exec @ARGV' -- $((MINUTES * 60)) "$CLAUDE" -p "$(cat "$PROMPT")" \
      --model "$MODEL" --permission-mode "$MODE" --output-format text ${SETTINGSFLAG[@]+"${SETTINGSFLAG[@]}"} \
      < /dev/null > "$REPORT" 2> "$STDERR" )
CODE=$?
echo "exit=$CODE after $(( $(date +%s) - START ))s; stderr in $STDERR"
if grep -qi "not logged in" "$REPORT" "$STDERR" 2>/dev/null; then
  cat >&2 <<'MSG'

The claude CLI has no credentials of its own on this machine, so it cannot run as Claude.
Fix it once, either way:
  * run `claude /login` in a terminal (a desktop-app session does not give the CLI its login), or
  * export ANTHROPIC_API_KEY, or
  * pass -S PROFILE.json to use a settings profile (~/.claude/profiles/ holds any you have;
    a profile with ANTHROPIC_BASE_URL points the CLI at another provider, not at Claude).
Inside a Claude Code session, dispatch a subagent instead: it needs no CLI login.
MSG
fi
if [ -s "$REPORT" ]; then echo "=== report ($REPORT) ==="; cat "$REPORT"
else echo "=== no output; last lines of stderr ==="; tail -n 20 "$STDERR"; fi
exit $CODE
