# Changelog

All notable changes to this package. The version lives in
`.claude-plugin/plugin.json` and `gemini-extension.json`; keep them equal.

## 0.2.0 — 2026-09-10

Works on a laptop that has none of this set up yet, and reads as instructions rather than as a
manual.

- `install.sh setup` — the guided path. Looks for each assistant, and when one is missing asks
  whether you have an account before offering to install it, showing the exact command first.
  When one is installed but not signed in, it offers to start the sign-in. Nothing is installed,
  signed into, or written without a yes. `--yes` accepts everything; a non-interactive shell
  takes each default and says so rather than hanging.
- `check` now reports sign-in state per assistant, not just which commands exist, and says what
  to run when one is missing. Antigravity's sign-in is reported as unknown, because it cannot be
  established without a network call.
- The agents live in one registry of small functions, so adding a fourth is a handful of lines.
- `tests/install_test.sh` — 31 tests over a throwaway home directory and throwaway projects:
  exit codes, idempotency, byte-for-byte uninstall, `--dry-run`, `--copy`, and the
  nothing-installed path.
- README rewritten for someone who does not live in a terminal, with the reference material kept
  below it.
- Written for bash 3.2, which is what macOS ships.
- Fixed: `check` aborted after the first agent, because a non-zero status captured with `;`
  trips `set -e`.

## 0.1.0 — 2026-09-10

First packaged release. The scripts and procedure were written on 2026-09-08 from four days of
running these CLIs against real work.

- `skills/external-agents/` — the skill: `SKILL.md`, `reference.md`, four wrapper scripts, three
  prompt templates.
- Claude Code plugin format: `.claude-plugin/plugin.json`, and `.claude-plugin/marketplace.json`
  so the repository is its own marketplace.
- `install.sh` — `install`, `check`, `uninstall`, `version`; `--global` or `--project DIR`;
  `--agent claude,codex,antigravity`; `--copy` to vendor the skill into a project instead of
  linking it.
- `integrations/*.manifest.json` — one manifest per agent, so adding an agent is data, not code.
- `gemini-extension.json`, root `AGENTS.md` — for Antigravity, Codex and any other agent that
  reads an instructions file rather than loading Claude skills.
- `--agent` selects the caller, not the callee: installing for one agent lets that agent call the
  other two, and leaves the rest of the machine alone. Documented in the README.
- `--project` on a path that does not exist says so and exits 2, rather than failing inside `cd`.
