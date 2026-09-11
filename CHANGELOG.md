# Changelog

All notable changes to this package. The version lives in
`.claude-plugin/plugin.json` and `gemini-extension.json`; keep them equal.

## 0.1.0 — 2026-09-10

First packaged release. The scripts and procedure were written on 2026-09-08 from four days of
running these CLIs against real work.

- `skills/external-models/` — the skill: `SKILL.md`, `reference.md`, four wrapper scripts, three
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
