#!/usr/bin/env bash
# external-models: install, verify and remove the skill for each agent on this machine.
#
#   ./install.sh install   [--global | --project DIR] [--agent LIST] [--copy] [--force] [--dry-run]
#   ./install.sh check     [--project DIR]
#   ./install.sh uninstall [--global | --project DIR] [--agent LIST] [--dry-run]
#   ./install.sh version
#
# --agent takes a comma-separated list from: claude, codex, antigravity. The default is every
# agent whose CLI is on PATH. Claude gets a skill directory; the others get a marked block in
# their instructions file, which `uninstall` removes exactly.
set -euo pipefail

HOME_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SKILL_SRC="$HOME_DIR/skills/external-models"
NAME=external-models
BEGIN="<!-- $NAME:begin (managed by install.sh; edit the package, not this block) -->"
END="<!-- $NAME:end -->"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME_DIR/.claude-plugin/plugin.json" | head -1)

CMD=${1:-}; shift || true
SCOPE=global; PROJECT=""; AGENTS=""; COPY=0; FORCE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --global) SCOPE=global; shift;;
    --project) SCOPE=project; PROJECT=${2:-$PWD}; [ $# -ge 2 ] && shift 2 || shift;;
    --agent) AGENTS=${2:-}; shift 2;;
    --copy) COPY=1; shift;;
    --force) FORCE=1; shift;;
    --dry-run) DRY=1; shift;;
    -h|--help) CMD=help; shift;;
    *) echo "unknown option $1" >&2; exit 2;;
  esac
done
[ "$SCOPE" = project ] && [ -z "$PROJECT" ] && PROJECT=$PWD
[ "$SCOPE" = project ] && PROJECT=$(cd "$PROJECT" && pwd -P)

say() { printf '%s\n' "$*"; }
run() { if [ $DRY -eq 1 ]; then say "  would: $*"; else eval "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }

detect_agents() {
  local found=""
  have claude && found="claude"
  have codex && found="${found:+$found,}codex"
  have agy && found="${found:+$found,}antigravity"
  printf '%s' "$found"
}
selected() { case ",$AGENTS," in *",$1,"*) return 0;; *) return 1;; esac; }

# --- one marked block in an instructions file, idempotent ------------------------------------
pointer_body() {
  cat <<EOF
$BEGIN
## Running another model

Claude, Codex and Antigravity are installed on this machine and you can call any of them for a
review, a second opinion, a plan gate, or a one-shot question. The procedure, the wrapper scripts
and the prompt templates are at \`$HOME_DIR/AGENTS.md\`. Read that file before invoking another
agent by hand: the wrappers close traps (a working tree a reviewer must not share, a plan gate
that stops without a report, runaway nesting) that cost hours when hit directly.
$END
EOF
}

write_pointer() {
  local file=$1
  if [ -f "$file" ] && grep -qF "$BEGIN" "$file" 2>/dev/null; then
    if [ $FORCE -eq 1 ]; then
      say "  refreshing the block in $file"
      [ $DRY -eq 1 ] || { strip_pointer "$file"; printf '%s\n' "$(pointer_body)" >> "$file"; }
    else
      say "  already present in $file (use --force to refresh)"
    fi
    return
  fi
  say "  adding the block to $file"
  if [ $DRY -eq 0 ]; then
    mkdir -p "$(dirname "$file")"
    [ -s "$file" ] && printf '\n' >> "$file"
    printf '%s\n' "$(pointer_body)" >> "$file"
  fi
}

strip_pointer() {
  local file=$1
  [ -f "$file" ] || return 0
  grep -qF "$BEGIN" "$file" || { say "  no block in $file"; return 0; }
  say "  removing the block from $file"
  [ $DRY -eq 1 ] && return 0
  awk -v b="$BEGIN" -v e="$END" 'index($0,b){skip=1} !skip{print} index($0,e){skip=0}' "$file" > "$file.tmp"
  # collapse a trailing run of blank lines the removal may leave
  awk 'BEGIN{n=0} {lines[NR]=$0} END{last=NR; while(last>0 && lines[last]~/^[[:space:]]*$/) last--; for(i=1;i<=last;i++) print lines[i]}' "$file.tmp" > "$file"
  rm -f "$file.tmp"
}

# --- the skill directory for Claude Code ------------------------------------------------------
claude_dest() {
  if [ "$SCOPE" = global ]; then printf '%s' "$HOME/.claude/skills/$NAME"
  else printf '%s' "$PROJECT/.claude/skills/$NAME"; fi
}

install_claude() {
  local dest; dest=$(claude_dest)
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ $FORCE -eq 1 ]; then run "rm -rf '$dest'"; else say "  already at $dest (use --force to replace)"; return; fi
  fi
  run "mkdir -p '$(dirname "$dest")'"
  if [ $COPY -eq 1 ]; then
    say "  copying the skill to $dest"
    run "cp -R '$SKILL_SRC' '$dest'"
  else
    say "  linking $dest -> $SKILL_SRC"
    run "ln -s '$SKILL_SRC' '$dest'"
  fi
  if [ "$SCOPE" = global ]; then
    # Some setups keep a shared skills directory for every agent; mirror there when it exists.
    if [ -d "$HOME/.agents/skills" ] && [ ! -e "$HOME/.agents/skills/$NAME" ]; then
      say "  linking $HOME/.agents/skills/$NAME -> $SKILL_SRC (shared skills directory)"
      run "ln -s '$SKILL_SRC' '$HOME/.agents/skills/$NAME'"
    fi
    say "  native alternative: /plugin marketplace add $HOME_DIR   then   /plugin install $NAME@external-agents"
  fi
}

uninstall_claude() {
  local dest; dest=$(claude_dest)
  if [ -L "$dest" ] || [ -d "$dest" ]; then say "  removing $dest"; run "rm -rf '$dest'"; else say "  nothing at $dest"; fi
  if [ "$SCOPE" = global ] && [ -L "$HOME/.agents/skills/$NAME" ]; then
    say "  removing $HOME/.agents/skills/$NAME"; run "rm -f '$HOME/.agents/skills/$NAME'"
  fi
  # Leave nothing empty behind; rmdir refuses a directory that still holds anything.
  [ $DRY -eq 1 ] || rmdir "$(dirname "$dest")" "$(dirname "$(dirname "$dest")")" 2>/dev/null || true
}

case "$CMD" in
  install)
    [ -z "$AGENTS" ] && AGENTS=$(detect_agents)
    [ -z "$AGENTS" ] && { echo "no agent CLI found on PATH; pass --agent explicitly" >&2; exit 1; }
    say "external-models $VERSION -> $SCOPE${PROJECT:+ ($PROJECT)}   agents: $AGENTS"
    if selected claude; then say "claude:"; install_claude; fi
    if selected codex; then say "codex:"; write_pointer "$([ "$SCOPE" = global ] && echo "$HOME/.codex/AGENTS.md" || echo "$PROJECT/AGENTS.md")"; fi
    if selected antigravity; then say "antigravity:"; write_pointer "$([ "$SCOPE" = global ] && echo "$HOME/.gemini/GEMINI.md" || echo "$PROJECT/GEMINI.md")"; fi
    say 'done. Run "./install.sh check" to verify it.'
    ;;
  uninstall)
    [ -z "$AGENTS" ] && AGENTS="claude,codex,antigravity"
    say "removing external-models from $SCOPE${PROJECT:+ ($PROJECT)}   agents: $AGENTS"
    if selected claude; then say "claude:"; uninstall_claude; fi
    if selected codex; then say "codex:"; strip_pointer "$([ "$SCOPE" = global ] && echo "$HOME/.codex/AGENTS.md" || echo "$PROJECT/AGENTS.md")"; fi
    if selected antigravity; then say "antigravity:"; strip_pointer "$([ "$SCOPE" = global ] && echo "$HOME/.gemini/GEMINI.md" || echo "$PROJECT/GEMINI.md")"; fi
    say "done."
    ;;
  check)
    say "external-models $VERSION"
    say "package:  $HOME_DIR"
    say ""
    say "CLIs"
    for pair in "claude:Claude" "codex:Codex" "agy:Antigravity"; do
      bin=${pair%%:*}; label=${pair##*:}
      if have "$bin"; then
        v=$("$bin" --version 2>/dev/null | head -1 | tr -d '\n')
        printf '  %-14s %-38s %s\n' "$label" "$(command -v "$bin")" "${v:-version unknown}"
      else
        printf '  %-14s %s\n' "$label" "not on PATH"
      fi
    done
    say ""
    say "Claude CLI authentication"
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then say "  ANTHROPIC_API_KEY is set"
    elif [ -f "$HOME/.claude/.credentials.json" ]; then say "  ~/.claude/.credentials.json present"
    elif security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1; then say "  login found in the keychain"
    else say "  none found: run-claude.sh cannot run as Claude until you run 'claude /login' in a terminal,"
         say "  export ANTHROPIC_API_KEY, or pass -S PROFILE.json. Codex and Antigravity need no setup."
    fi
    say ""
    say "Installed for"
    d="$HOME/.claude/skills/$NAME"; [ -e "$d" ] && say "  claude, global:  $d -> $(readlink "$d" 2>/dev/null || echo 'copy')" || say "  claude, global:  not installed"
    [ "$SCOPE" = project ] && { d="$PROJECT/.claude/skills/$NAME"; [ -e "$d" ] && say "  claude, project: $d" || say "  claude, project: not installed"; }
    for f in "$HOME/.codex/AGENTS.md:codex, global" "$HOME/.gemini/GEMINI.md:antigravity, global"; do
      p=${f%%:*}; l=${f##*:}
      if [ -f "$p" ] && grep -qF "$BEGIN" "$p" 2>/dev/null; then say "  $l: pointer in $p"; else say "  $l: no pointer"; fi
    done
    ;;
  version) say "external-models $VERSION ($HOME_DIR)";;
  help|"") awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0";;
  *) echo "unknown command: $CMD (try: install, check, uninstall, version)" >&2; exit 2;;
esac
