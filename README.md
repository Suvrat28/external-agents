# external-models

Run Claude, Codex and Antigravity from one another, from a conversation or a shell.

One model reviewing another's work finds what the author cannot see. Three independent readings
of the same branch on 2026-09-08 found nine defects that single readings had missed, one of them
blocking. This packages that: wrapper scripts that close the traps, a diff packager that gives
each reviewer its own disposable copy of the repository, and prompt templates that end in a fixed
report format so answers from different models can be compared.

## Install

**Claude Code, the native way.** The repository is its own plugin marketplace:

```
/plugin marketplace add ~/Developer/8-resources/1-external-agents
/plugin install external-models@external-agents
```

**Any agent, including per-project.** `install.sh` links the skill and writes a marked block into
each agent's instructions file:

```bash
./install.sh install --global                        # every agent whose CLI is on PATH
./install.sh install --global --agent claude,codex   # or name them
./install.sh install --project ~/code/some-repo      # .claude/skills + AGENTS.md in that project
./install.sh install --project . --copy              # vendor the skill in, to commit with the repo
./install.sh check                                   # CLIs, versions, authentication, what is installed
./install.sh uninstall --global                      # removes exactly what install added
```

Installing is idempotent, `--dry-run` shows the plan, and `--force` refreshes in place.
Uninstall removes the marked block and leaves the rest of the file byte-for-byte unchanged.

| Agent | What install does |
|---|---|
| Claude Code | Symlinks (or copies, with `--copy`) the skill into `~/.claude/skills/` or `<project>/.claude/skills/`, and mirrors into `~/.agents/skills/` when that shared directory exists |
| Codex | Writes a marked pointer block into `~/.codex/AGENTS.md` or `<project>/AGENTS.md` |
| Antigravity | Writes the same block into `~/.gemini/GEMINI.md` or `<project>/GEMINI.md` |

## Calling it

**From Claude Code:** type `/external-models`, or ask for what you want ("get a Codex review of
this branch", "second opinion from Antigravity"). The description matches on those words.

**From Codex or Antigravity:** the pointer their instructions now carry leads to `AGENTS.md`.

**From a shell or a cron job:** call the scripts under `skills/external-models/scripts/`.

All three wrappers take the same shape:

```bash
skills/external-models/scripts/run-<tool>.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-C DIR] [-t MINUTES]
```

`-C DIR` is a **disposable copy** of the repository, not your checkout. `-t` caps the wall clock.
Each prints its report and saves it to `-o`.

## Layout

| Path | What |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest: name, version, author, licence |
| `.claude-plugin/marketplace.json` | Makes the repository its own marketplace |
| `skills/external-models/SKILL.md` | The procedure, as a Claude Code skill |
| `skills/external-models/reference.md` | Each CLI's flags, traps, authentication, timings from real runs |
| `skills/external-models/scripts/` | `run-claude.sh`, `run-codex.sh`, `run-agy.sh`, `review-package.sh` |
| `skills/external-models/templates/` | `review.md`, `gate.md`, `implement.md` |
| `AGENTS.md` | The same procedure for any agent that does not load Claude skills |
| `integrations/*.manifest.json` | One manifest per agent, so adding an agent is data, not code |
| `gemini-extension.json` | Antigravity and Gemini extension manifest |
| `install.sh` | `install`, `check`, `uninstall`, `version` |

Borrowed from [GitHub Spec Kit](https://github.com/github/spec-kit): a `check` command that
verifies the tooling before you rely on it, manifest-driven agent integrations, and one installer
that targets either a project or the whole machine.

## Authentication

`run-claude.sh` needs the `claude` CLI to have its own login (`claude /login` once in a terminal)
or an exported `ANTHROPIC_API_KEY`. A desktop-app session's authentication belongs to the app and
is not inherited by a child process. Codex and Antigravity need no such setup. `./install.sh check`
tells you which of these is true right now.

## The traps these scripts close

1. `codex exec` blocks forever when stdin is an open pipe. One pass hung seventeen hours.
2. Codex writes its report only as its final message, captured by `-o`.
3. Antigravity stops at a plan gate in `--mode plan`; its prompt must be attached to `--print=`,
   and a Gemini model name carries its own effort, so `--effort` beside it is refused.
4. The `claude` CLI needs its own credentials, and an interactive shell function may point it at
   another provider.
5. A reviewer must not share your working tree. Every wrapper refuses a repository's main
   checkout when the run could edit it.
6. Agents calling agents. `EXTERNAL_MODELS_DEPTH` refuses past two levels.

`skills/external-models/reference.md` has the detail, including what each tool did on real work.

## Licence

MIT. See `LICENSE`.
