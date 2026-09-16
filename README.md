# external-models

**Let your coding assistants ask each other for a second opinion.**

You may have more than one AI coding assistant: Claude Code, Codex, Antigravity. Each is strong
in different ways, and each is bad at spotting its own mistakes. This package teaches them to
call one another, so you can say "get a second opinion on this" and mean it.

It is not a new assistant. It is a small set of instructions and scripts that the assistants you
already have will read and use.

**Why bother.** On one real piece of work, three assistants reviewed the same change
independently. Together they found nine genuine problems that any one of them alone had missed,
including one that would have broken things after merging.

---

## Getting started

### Step 1: open a terminal in this folder

On a Mac, open the **Terminal** app and type `cd `, then drag this folder onto the window and
press Enter.

### Step 2: run the setup

```bash
./install.sh setup
```

That is the whole installation. It will:

1. Look for each assistant on your computer.
2. If one is missing, ask whether you have an account for it. If you say no, it tells you where
   to sign up and moves on. If you say yes, it offers to install it for you and shows you the
   exact command before running anything.
3. If one is installed but not signed in, it offers to start the sign-in, which opens your
   browser.
4. Set everything up for whichever assistants are ready.

It never installs anything, signs into anything, or changes a file without asking you first.
You can say no to any question and the rest still works.

### Step 3: use it

Just ask, in your own words, in whichever assistant you are talking to:

> "Get a Codex review of this branch before I merge it."

> "Ask Antigravity for a second opinion on this design."

> "Have Claude check this plan against the brief."

The assistant will know what to do, run the other one in the background, and come back with the
findings. A review usually takes five to twenty minutes.

---

## If something does not look right

Run this at any time. It is safe and changes nothing:

```bash
./install.sh check
```

It prints, in plain terms, which assistants are on your computer, whether each is signed in, and
where this package is installed. Common answers:

| What it says | What to do |
|---|---|
| `not installed` | Run `./install.sh setup` and say yes when it offers to install |
| `NOT signed in -- run: codex login` | Run that command; it opens your browser |
| `sign-in unknown` | Antigravity cannot be checked without going online. Run `agy models`; if it lists models, you are signed in |
| `Claude Code ... NOT signed in` | Run `claude /login` in a terminal. Being signed into the Claude desktop app is not the same thing |

You do not need every assistant. One is enough to start, and this works with whichever ones you
have.

---

## Installing it for one project only

By default, setup applies to your whole computer. To set it up for a single project instead:

```bash
./install.sh install --project ~/path/to/your-project
```

To include the package inside that project, so anyone who clones it gets it too:

```bash
./install.sh install --project ~/path/to/your-project --copy
```

## Removing it

```bash
./install.sh uninstall --global                      # from the whole computer
./install.sh uninstall --project ~/path/to/project   # from one project
```

It removes only what it added. Any file it edited goes back to exactly what it was before.

---

## For the technically minded

### Commands

```bash
./install.sh setup     [--global | --project DIR] [--yes]
./install.sh install   [--global | --project DIR] [--agent LIST] [--copy] [--force] [--dry-run]
./install.sh check     [--project DIR]
./install.sh uninstall [--global | --project DIR] [--agent LIST] [--dry-run]
./install.sh version
```

`setup` is interactive and forgiving. `install` never prompts, which suits scripts and CI.
`--dry-run` prints the plan without doing anything. `--yes` answers every question yes.
Exit codes: `0` success, `1` nothing usable found, `2` bad usage.

### Who calls, and who gets called

`--agent` names the **caller**: the assistant that learns to reach for another model. It does not
limit which models that caller may then run.

| Command | Result |
|---|---|
| `install --global --agent codex` | Codex, in every project, can call Claude and Antigravity. Nothing else changes |
| `install --global` | Every assistant on the machine can call the others |
| `install --project . --agent codex` | The same, limited to one project |
| `install --project .` | Every assistant, limited to one project |

With no `--agent`, it picks every assistant whose command it can find.

### Claude Code users: the native route

This repository is also a Claude Code plugin marketplace, if you prefer that to the installer:

```
/plugin marketplace add /path/to/this/folder
/plugin install external-models@external-agents
```

### What gets changed on your computer

| Assistant | What is added |
|---|---|
| Claude Code | A link to the skill in `~/.claude/skills/` (or the project's `.claude/skills/`) |
| Codex | A marked block in `~/.codex/AGENTS.md` (or the project's `AGENTS.md`) |
| Antigravity | The same block in `~/.gemini/GEMINI.md` (or the project's `GEMINI.md`) |

Every block is wrapped in `external-models:begin` / `end` markers, which is how uninstall removes
exactly its own text and nothing else.

### Using the scripts directly

```bash
skills/external-models/scripts/run-codex.sh  -p PROMPT_FILE -o REPORT_FILE -C WORKTREE -e xhigh -t 90
skills/external-models/scripts/run-agy.sh    -p PROMPT_FILE -o REPORT_FILE -C WORKTREE -m gemini-3.8-flash-high
skills/external-models/scripts/run-claude.sh -p PROMPT_FILE -o REPORT_FILE -C WORKTREE -m opus
skills/external-models/scripts/review-package.sh BASE HEAD OUTDIR --worktree codex
```

`-C` is the working directory, and it should be a throwaway copy of your project rather than the
one you are working in: `git worktree add --detach DIR HEAD` makes one. `-t` caps how long the
run may take, in minutes. Each script prints its report and saves it to `-o`.

### Layout

| Path | What |
|---|---|
| `install.sh` | Setup, installation, checking, removal |
| `tests/install_test.sh` | 31 tests, run against a throwaway home directory |
| `skills/external-models/SKILL.md` | The procedure, as a Claude Code skill |
| `skills/external-models/reference.md` | Each tool's flags, traps, sign-in, and timings from real runs |
| `skills/external-models/scripts/` | The four scripts above |
| `skills/external-models/templates/` | Prompt templates: review, plan gate, implementation |
| `AGENTS.md` | The same procedure for assistants that do not read Claude skills |
| `integrations/*.manifest.json` | One file per assistant, so adding another is data, not code |
| `.claude-plugin/` | Plugin and marketplace manifests for Claude Code |

### Things that would otherwise waste your afternoon

1. `codex exec` waits forever if its input is left open. One run hung for seventeen hours.
2. Codex only writes its report as its very last message.
3. Antigravity stops and waits for approval unless told otherwise, and rejects an effort setting
   when the model name already contains one.
4. The `claude` command needs its own sign-in, separate from the desktop app.
5. A reviewer must never work in your live folder. Every script refuses to.
6. Assistants calling assistants can loop. They refuse to nest more than two deep.

`skills/external-models/reference.md` has the detail.

### A few words explained

| Word | Meaning |
|---|---|
| CLI | The version of an assistant you run by typing in a terminal |
| Branch, diff | A set of changes you are considering merging into your project |
| Worktree | A second, disposable copy of your project, so a reviewer cannot disturb your work |
| Plan gate | Having a second model check a plan before any code is written |

### Compatibility

Written for macOS and Linux, in the version of bash that macOS ships. Tested on macOS. On
Windows it needs WSL or Git Bash. No administrator rights, and nothing installs without asking.

## Licence

MIT. See `LICENSE`.
