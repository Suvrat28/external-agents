#!/usr/bin/env bash
# external-agents: set up, install, verify and remove the skill that lets your coding agents
# call one another.
#
#   ./install.sh setup     [--global | --project DIR] [--yes]
#   ./install.sh install   [--global | --project DIR] [--agent LIST] [--copy] [--force] [--dry-run]
#   ./install.sh check     [--project DIR]
#   ./install.sh uninstall [--global | --project DIR] [--agent LIST] [--dry-run]
#   ./install.sh version
#
# setup is the friendly one: it looks for each agent's command, offers to install or log in
# what is missing, then installs the skill. install is the unattended one and never prompts.
# --agent takes a comma-separated list from: claude, codex, antigravity. It names the CALLER --
# the agent that learns to reach for another model -- not which models it may call.
#
# Written for bash 3.2, which is what macOS ships. No associative arrays, no sudo, no network
# call unless you say yes to one.
set -euo pipefail

HOME_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
SKILL_SRC="$HOME_DIR/skills/external-agents"
NAME=external-agents
BEGIN="<!-- $NAME:begin (managed by install.sh; edit the package, not this block) -->"
END="<!-- $NAME:end -->"
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME_DIR/.claude-plugin/plugin.json" | head -1)
ALL_AGENTS="claude codex antigravity"

CMD=${1:-}; shift 2>/dev/null || true
SCOPE=global; PROJECT=""; AGENTS=""; COPY=0; FORCE=0; DRY=0; ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --global) SCOPE=global; shift;;
    --project) SCOPE=project; PROJECT=${2:-$PWD}; [ $# -ge 2 ] && shift 2 || shift;;
    --agent) AGENTS=${2:-}; shift 2;;
    --copy) COPY=1; shift;;
    --force) FORCE=1; shift;;
    --dry-run) DRY=1; shift;;
    -y|--yes) ASSUME_YES=1; shift;;
    -h|--help) CMD=help; shift;;
    *) echo "unknown option: $1" >&2; echo "try: ./install.sh help" >&2; exit 2;;
  esac
done
if [ "$SCOPE" = project ]; then
  [ -z "$PROJECT" ] && PROJECT=$PWD
  if [ ! -d "$PROJECT" ]; then
    echo "no such directory: $PROJECT" >&2
    echo "--project takes an existing project; create it first, or use --global for the whole machine." >&2
    exit 2
  fi
  PROJECT=$(cd "$PROJECT" && pwd -P)
fi

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }
run()  { if [ $DRY -eq 1 ]; then say "  would: $*"; else eval "$@"; fi; }
have() { command -v "$1" >/dev/null 2>&1; }
interactive() { [ -t 0 ] && [ -t 1 ]; }

# Ask a yes/no question. --yes answers yes; a non-interactive shell takes the default and says so.
ask_yn() {
  local q=$1 default=${2:-n} reply
  if [ $ASSUME_YES -eq 1 ]; then say "  $q yes (--yes)"; return 0; fi
  if ! interactive; then
    say "  $q [$default, not a terminal]"
    [ "$default" = y ] && return 0 || return 1
  fi
  while true; do
    if [ "$default" = y ]; then printf '  %s [Y/n] ' "$q"; else printf '  %s [y/N] ' "$q"; fi
    read -r reply </dev/tty || reply=""
    [ -z "$reply" ] && reply=$default
    case "$reply" in [Yy]*) return 0;; [Nn]*) return 1;; esac
  done
}

# ---------------------------------------------------------------- the agent registry ---------
# One place to add an agent. Everything else reads these.
agent_bin() {   case $1 in claude) echo claude;; codex) echo codex;; antigravity) echo agy;; esac; }
agent_label() { case $1 in claude) echo "Claude Code";; codex) echo "Codex";; antigravity) echo "Antigravity";; esac; }
agent_site() {
  case $1 in
    claude) echo "https://claude.ai/code";;
    codex) echo "https://chatgpt.com (a ChatGPT plan includes Codex)";;
    antigravity) echo "https://antigravity.google.com";;
  esac
}
# A command we can offer to run, or empty when the tool has no scripted install we can vouch for.
agent_install_cmd() {
  case $1 in
    claude) echo "curl -fsSL https://claude.ai/install.sh | bash";;
    codex) if have npm; then echo "npm install -g @openai/codex"; else echo ""; fi;;
    antigravity) echo "";;
  esac
}
agent_install_note() {
  case $1 in
    claude) echo "or: npm install -g @anthropic-ai/claude-code";;
    codex) if have npm; then echo "installs into your npm prefix, no sudo"; else echo "needs Node and npm first: https://nodejs.org"; fi;;
    antigravity) echo "download it from the site above and put 'agy' on your PATH";;
  esac
}
agent_login_cmd() {
  case $1 in
    claude) echo "claude /login";;
    codex) echo "codex login";;
    antigravity) echo "agy models";;
  esac
}
agent_login_note() {
  case $1 in
    claude) echo "opens a browser; a desktop-app session does not log the command line in";;
    codex) echo "opens a browser";;
    antigravity) echo "the first run opens a browser to sign in";;
  esac
}
# 0 = signed in, 1 = not signed in, 2 = cannot tell without a network call
agent_auth() {
  case $1 in
    claude)
      [ -n "${ANTHROPIC_API_KEY:-}" ] && return 0
      [ -f "$HOME/.claude/.credentials.json" ] && return 0
      security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 && return 0
      return 1;;
    codex)
      have codex || return 1
      codex login status >/dev/null 2>&1 && return 0
      return 1;;
    antigravity) return 2;;
  esac
}
agent_auth_text() {
  case $1 in
    claude) echo "an API key, ~/.claude/.credentials.json, or a keychain login";;
    codex) echo "codex login status";;
    antigravity) echo "cannot be checked without a network call; run 'agy models' to be sure";;
  esac
}
selected() { case " $AGENTS " in *" $1 "*) return 0;; *) return 1;; esac; }
detect_agents() {
  local id found=""
  for id in $ALL_AGENTS; do have "$(agent_bin "$id")" && found="$found $id"; done
  printf '%s' "${found# }"
}
normalise_agents() {
  # accept commas or spaces, validate every name
  local raw id ok out=""
  raw=$(printf '%s' "$1" | tr ',' ' ')
  for id in $raw; do
    ok=0
    case " $ALL_AGENTS " in *" $id "*) ok=1;; esac
    [ $ok -eq 1 ] || { warn "unknown agent: $id (known: $(echo $ALL_AGENTS | tr ' ' ', '))"; exit 2; }
    out="$out $id"
  done
  printf '%s' "${out# }"
}

# ---------------------------------------------------------------- instructions pointers ------
pointer_file() {
  case $1 in
    codex) [ "$SCOPE" = global ] && echo "$HOME/.codex/AGENTS.md" || echo "$PROJECT/AGENTS.md";;
    antigravity) [ "$SCOPE" = global ] && echo "$HOME/.gemini/GEMINI.md" || echo "$PROJECT/GEMINI.md";;
  esac
}
pointer_body() {
  cat <<EOF
$BEGIN
## Running another model

Claude, Codex and Antigravity may be installed on this machine, and you can call any of them for
a review, a second opinion, a plan gate, or a one-shot question. The procedure, the wrapper
scripts and the prompt templates are at \`$HOME_DIR/AGENTS.md\`. Read that file before invoking
another agent by hand: the wrappers close traps (a working tree a reviewer must not share, a plan
gate that stops without a report, runaway nesting) that cost hours when hit directly.
$END
EOF
}
write_pointer() {
  local file=$1
  if [ -f "$file" ] && grep -qF "$BEGIN" "$file" 2>/dev/null; then
    if [ $FORCE -eq 1 ]; then
      say "  refreshing the block in $file"
      [ $DRY -eq 1 ] || { strip_pointer "$file" >/dev/null; printf '%s\n' "$(pointer_body)" >> "$file"; }
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
  [ -f "$file" ] || { say "  no block in $file"; return 0; }
  grep -qF "$BEGIN" "$file" || { say "  no block in $file"; return 0; }
  say "  removing the block from $file"
  [ $DRY -eq 1 ] && return 0
  awk -v b="$BEGIN" -v e="$END" 'index($0,b){skip=1} !skip{print} index($0,e){skip=0}' "$file" > "$file.tmp"
  awk '{lines[NR]=$0} END{last=NR; while(last>0 && lines[last]~/^[[:space:]]*$/) last--; for(i=1;i<=last;i++) print lines[i]}' "$file.tmp" > "$file"
  rm -f "$file.tmp"
}

# ---------------------------------------------------------------- the Claude skill directory -
claude_dest() {
  [ "$SCOPE" = global ] && echo "$HOME/.claude/skills/$NAME" || echo "$PROJECT/.claude/skills/$NAME"
}
install_claude() {
  local dest; dest=$(claude_dest)
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if [ $FORCE -eq 1 ]; then run "rm -rf '$dest'"; else say "  already at $dest (use --force to replace)"; return; fi
  fi
  run "mkdir -p '$(dirname "$dest")'"
  if [ $COPY -eq 1 ]; then
    say "  copying the skill to $dest"; run "cp -R '$SKILL_SRC' '$dest'"
  else
    say "  linking $dest -> $SKILL_SRC"; run "ln -s '$SKILL_SRC' '$dest'"
  fi
  if [ "$SCOPE" = global ]; then
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
  [ $DRY -eq 1 ] || rmdir "$(dirname "$dest")" "$(dirname "$(dirname "$dest")")" 2>/dev/null || true
}

do_install_one() {
  case $1 in
    claude) say "$(agent_label claude):"; install_claude;;
    *) say "$(agent_label "$1"):"; write_pointer "$(pointer_file "$1")";;
  esac
}
do_uninstall_one() {
  case $1 in
    claude) say "$(agent_label claude):"; uninstall_claude;;
    *) say "$(agent_label "$1"):"; strip_pointer "$(pointer_file "$1")";;
  esac
}

# ---------------------------------------------------------------- setup, the guided path -----
setup_agent() {
  local id=$1 bin label; bin=$(agent_bin "$id"); label=$(agent_label "$id")
  say ""
  say "$label"
  if ! have "$bin"; then
    say "  the '$bin' command is not on this machine."
    if ! ask_yn "Do you have an account for $label?" n; then
      say "  skipping $label. You can sign up at $(agent_site "$id") and run this again."
      return 1
    fi
    local cmd; cmd=$(agent_install_cmd "$id")
    if [ -z "$cmd" ]; then
      say "  there is no one-line install for $label here."
      say "  $(agent_install_note "$id")"
      say "  start at: $(agent_site "$id")"
      say "  then run this again."
      return 1
    fi
    say "  install command: $cmd"
    say "  ($(agent_install_note "$id"))"
    if ask_yn "Run that now?" n; then
      if [ $DRY -eq 1 ]; then
        say "  would: $cmd"
        return 1
      fi
      eval "$cmd" || { warn "  the install command failed; run it by hand and try again"; return 1; }
      have "$bin" || { say "  installed, but '$bin' is not on your PATH yet. Open a new terminal and run this again."; return 1; }
      say "  installed."
    else
      say "  skipping $label for now."
      return 1
    fi
  else
    say "  found: $(command -v "$bin")"
  fi

  local st=0; agent_auth "$id" || st=$?
  if [ $st -eq 0 ]; then
    say "  signed in."
  elif [ $st -eq 2 ]; then
    say "  sign-in cannot be checked here ($(agent_auth_text "$id"))."
  else
    say "  not signed in."
    say "  sign-in command: $(agent_login_cmd "$id")  ($(agent_login_note "$id"))"
    if ask_yn "Run that now?" n; then
      if [ $DRY -eq 1 ]; then say "  would: $(agent_login_cmd "$id")"; else
        eval "$(agent_login_cmd "$id")" || warn "  sign-in did not complete; you can run it again later"
      fi
    else
      say "  you can sign in later; everything else will still be set up."
    fi
  fi
  return 0
}

# ---------------------------------------------------------------- commands -------------------
case "$CMD" in
  setup)
    say "external-agents $VERSION"
    say "Setting up for: $([ "$SCOPE" = global ] && echo "this machine" || echo "$PROJECT")"
    interactive || say "(not a terminal: questions take their default answer and nothing is installed for you)"
    usable=""
    for id in $ALL_AGENTS; do
      if setup_agent "$id"; then usable="$usable $id"; fi
    done
    usable=${usable# }
    say ""
    if [ -z "$usable" ]; then
      say "No agent is ready yet. Install at least one of them and run this again:"
      for id in $ALL_AGENTS; do say "  $(agent_label "$id"): $(agent_site "$id")"; done
      exit 1
    fi
    say "Installing the skill for:$(for id in $usable; do printf ' %s' "$(agent_label "$id")"; done)"
    AGENTS=$usable
    for id in $usable; do do_install_one "$id"; done
    say ""
    say "Done. Ask any of them for a review and it will know what to do."
    say "Run './install.sh check' at any time to see the state of things."
    ;;

  install)
    [ -z "$AGENTS" ] && AGENTS=$(detect_agents) || AGENTS=$(normalise_agents "$AGENTS")
    if [ -z "$AGENTS" ]; then
      warn "no agent command found on this machine (looked for: claude, codex, agy)."
      warn "run './install.sh setup' to be walked through installing one, or pass --agent explicitly."
      exit 1
    fi
    say "external-agents $VERSION -> $SCOPE${PROJECT:+ ($PROJECT)}   agents:$(for id in $AGENTS; do printf ' %s' "$id"; done)"
    for id in $AGENTS; do do_install_one "$id"; done
    say 'done. Run "./install.sh check" to verify it.'
    ;;

  uninstall)
    [ -z "$AGENTS" ] && AGENTS=$ALL_AGENTS || AGENTS=$(normalise_agents "$AGENTS")
    say "removing external-agents from $SCOPE${PROJECT:+ ($PROJECT)}   agents:$(for id in $AGENTS; do printf ' %s' "$id"; done)"
    for id in $AGENTS; do do_uninstall_one "$id"; done
    say "done."
    ;;

  check)
    say "external-agents $VERSION"
    say "package:  $HOME_DIR"
    say ""
    say "Agents on this machine"
    for id in $ALL_AGENTS; do
      bin=$(agent_bin "$id"); label=$(agent_label "$id")
      if have "$bin"; then
        v=$("$bin" --version 2>/dev/null | head -1 | tr -d '\n')
        printf '  %-13s %-34s %s\n' "$label" "$(command -v "$bin")" "${v:-version unknown}"
        st=0; agent_auth "$id" || st=$?
        case $st in
          0) printf '  %-13s signed in\n' "";;
          2) printf '  %-13s sign-in unknown (%s)\n' "" "$(agent_auth_text "$id")";;
          *) printf '  %-13s NOT signed in -- run: %s\n' "" "$(agent_login_cmd "$id")";;
        esac
      else
        printf '  %-13s not installed -- %s\n' "$label" "$(agent_site "$id")"
      fi
    done
    say ""
    say "Where the skill is installed"
    d="$HOME/.claude/skills/$NAME"
    if [ -L "$d" ]; then say "  Claude Code, this machine:  $d -> $(readlink "$d")"
    elif [ -d "$d" ]; then say "  Claude Code, this machine:  $d (copy)"
    else say "  Claude Code, this machine:  not installed"; fi
    if [ "$SCOPE" = project ]; then
      d="$PROJECT/.claude/skills/$NAME"
      [ -e "$d" ] && say "  Claude Code, this project:  $d" || say "  Claude Code, this project:  not installed"
    fi
    for id in codex antigravity; do
      for s in global project; do
        [ "$s" = project ] && [ "$SCOPE" != project ] && continue
        SAVED=$SCOPE; SCOPE=$s; f=$(pointer_file "$id"); SCOPE=$SAVED
        if [ -f "$f" ] && grep -qF "$BEGIN" "$f" 2>/dev/null; then
          say "  $(agent_label "$id"), this $([ "$s" = global ] && echo machine || echo project):  pointer in $f"
        else
          say "  $(agent_label "$id"), this $([ "$s" = global ] && echo machine || echo project):  not installed"
        fi
      done
    done
    ;;

  version) say "external-agents $VERSION ($HOME_DIR)";;
  help|"") awk 'NR>1 && /^#/ {sub(/^# ?/,""); print; next} NR>1 {exit}' "$0";;
  *) warn "unknown command: $CMD"; warn "try one of: setup, install, check, uninstall, version, help"; exit 2;;
esac
