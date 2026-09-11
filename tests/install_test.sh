#!/usr/bin/env bash
# Tests for install.sh. Every test runs against a throwaway HOME and throwaway projects, so
# running this never touches your real setup.
#
#   ./tests/install_test.sh
#
# Exits 0 when everything passes, 1 otherwise.
set -uo pipefail

PKG=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
INSTALL="$PKG/install.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/external-models-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }
yes_() { if eval "$2" >/dev/null 2>&1; then ok "$1"; else bad "$1" "expected true: $2"; fi; }
no_()  { if eval "$2" >/dev/null 2>&1; then bad "$1" "expected false: $2"; else ok "$1"; fi; }
# run install.sh in an isolated HOME
em()   { HOME="$TMP/home" "$INSTALL" "$@" >"$TMP/out" 2>"$TMP/err"; echo $?; }

mkdir -p "$TMP/home"
printf '%s\n' "external-models tests"

printf '\nthe basics\n'
is "version prints the version"  "$(HOME=$TMP/home "$INSTALL" version | grep -c 'external-models')" "1"
is "help prints usage"           "$(HOME=$TMP/home "$INSTALL" help | grep -c 'install.sh setup')" "1"
is "check exits 0"               "$(em check)" "0"
is "an unknown command exits 2"  "$(em frobnicate)" "2"
is "an unknown option exits 2"   "$(em install --nonesuch)" "2"
is "an unknown agent exits 2"    "$(em install --global --agent nonesuch)" "2"
is "a missing project exits 2"   "$(em install --project $TMP/absent --agent codex)" "2"

printf '\nglobal install, in a throwaway HOME\n'
is "install --agent codex exits 0"       "$(em install --global --agent codex)" "0"
yes_ "it writes the Codex pointer"        "grep -q 'external-models:begin' '$TMP/home/.codex/AGENTS.md'"
no_  "it leaves Claude alone"             "test -e '$TMP/home/.claude/skills/external-models'"
is "a second install is idempotent"      "$(em install --global --agent codex)" "0"
is "  and says so"                        "$(HOME=$TMP/home "$INSTALL" install --global --agent codex | grep -c 'already present')" "1"
is "install --agent claude exits 0"      "$(em install --global --agent claude)" "0"
yes_ "it links the skill"                 "test -L '$TMP/home/.claude/skills/external-models'"
is "  the link points at the package"     "$(readlink "$TMP/home/.claude/skills/external-models")" "$PKG/skills/external-models"
is "uninstall exits 0"                   "$(em uninstall --global)" "0"
no_  "the skill link is gone"             "test -e '$TMP/home/.claude/skills/external-models'"
no_  "the Codex block is gone"            "grep -q 'external-models:begin' '$TMP/home/.codex/AGENTS.md'"

printf '\nproject install leaves the file byte-for-byte\n'
PROJ="$TMP/proj"; mkdir -p "$PROJ"
printf '# My project\n\nSome instructions.\n' > "$PROJ/AGENTS.md"
cp "$PROJ/AGENTS.md" "$TMP/AGENTS.before"
is "install --project exits 0"           "$(em install --project $PROJ --agent codex,claude)" "0"
yes_ "the block is added"                 "grep -q 'external-models:begin' '$PROJ/AGENTS.md'"
yes_ "the skill lands in the project"     "test -e '$PROJ/.claude/skills/external-models'"
is "uninstall --project exits 0"         "$(em uninstall --project $PROJ --agent codex,claude)" "0"
yes_ "AGENTS.md is restored exactly"      "diff -q '$TMP/AGENTS.before' '$PROJ/AGENTS.md'"
no_  "the project skill is gone"          "test -e '$PROJ/.claude/skills/external-models'"

printf '\ndry run changes nothing\n'
PROJ2="$TMP/proj2"; mkdir -p "$PROJ2"
is "dry run exits 0"                     "$(em install --project $PROJ2 --agent codex --dry-run)" "0"
no_  "no AGENTS.md was created"           "test -e '$PROJ2/AGENTS.md'"

printf '\n--copy vendors the skill in\n'
PROJ3="$TMP/proj3"; mkdir -p "$PROJ3"
is "install --copy exits 0"              "$(em install --project $PROJ3 --agent claude --copy)" "0"
yes_ "it is a real directory, not a link" "test -d '$PROJ3/.claude/skills/external-models' && ! test -L '$PROJ3/.claude/skills/external-models'"
yes_ "the scripts came with it"           "test -x '$PROJ3/.claude/skills/external-models/scripts/run-codex.sh'"

printf '\nsetup without any agent installed\n'
OUT=$(HOME="$TMP/home" PATH=/usr/bin:/bin "$INSTALL" setup --dry-run 2>&1); CODE=$?
is "it exits 1 rather than hanging"      "$CODE" "1"
yes_ "it points at where to sign up"      "printf '%s' \"\$OUT\" | grep -q 'Install at least one of them'"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
