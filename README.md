# external-models

Run Claude, Codex and Antigravity from one another, from a conversation or a shell.

One model reviewing another's work finds what the author cannot see. Three independent readings
of the same branch on 2026-09-08 found nine defects that single readings had missed, one of them
blocking. This packages that: wrapper scripts that close the traps, a diff packager that gives
each reviewer its own disposable copy of the repository, and prompt templates that end in a fixed
report format.

## Layout

| Path | What |
|---|---|
| `SKILL.md` | The procedure, as a Claude Code skill |
| `AGENTS.md` | The same procedure for Codex and any other agent that does not load Claude skills |
| `reference.md` | Each CLI's flags, its traps, authentication, and timings from real runs |
| `scripts/run-claude.sh` | Claude, headless (`opus`, `sonnet`, `haiku`, `fable`) |
| `scripts/run-codex.sh` | Codex (`gpt-6-astra`) |
| `scripts/run-agy.sh` | Antigravity (`gemini-3.8-flash-high` and others) |
| `scripts/review-package.sh` | Builds `commits.txt`, `diffstat.txt`, `diff.patch` and a detached worktree per reviewer |
| `templates/` | `review.md`, `gate.md`, `implement.md` |

All three wrappers take the same shape:

```bash
scripts/run-<tool>.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-C DIR] [-t MINUTES]
```

`-C DIR` is a **disposable copy** of the repository, not your checkout. `-t` caps the wall clock.
Each prints its report and saves it to `-o`.

## Calling it

**From Claude Code:** type `/external-models`, or ask for what you want ("get a Codex review of
this branch", "second opinion from Antigravity"). The description matches on those words.

**From Codex or Antigravity:** point the agent at `AGENTS.md` in this directory. A machine-level
pointer in `~/.codex/AGENTS.md` does this for every Codex session.

**From a shell or a cron job:** call the scripts directly.

## Installing on another machine

```bash
git clone <this repo> ~/.agents/skills/external-models
ln -s ../../.agents/skills/external-models ~/.claude/skills/external-models
```

Then add a pointer to `~/.codex/AGENTS.md` so Codex sessions know it exists:

```markdown
## Running another model
The procedure and wrapper scripts are at `~/.agents/skills/external-models/AGENTS.md`.
```

`run-claude.sh` needs the `claude` CLI to have its own login (`claude /login` once in a terminal)
or an exported `ANTHROPIC_API_KEY`. A desktop-app session's authentication belongs to the app and
is not inherited by a child process. Codex and Antigravity need no such setup.

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

`reference.md` has the detail, including what each tool did on real work.
