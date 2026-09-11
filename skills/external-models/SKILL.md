---
name: external-models
description: "Use when work would benefit from a second model — an adversarial review of a branch or diff, a plan gate, an independent opinion, implementing a task in isolation, or any one-shot prompt. Runs Claude (claude), Codex (gpt-6-astra) and Antigravity (gemini and others) from one another through wrapper scripts that close the traps. Without them Codex hangs on stdin, Antigravity stops at a plan gate, and a reviewer edits your working tree."
---

# Running another model

Three command-line agents live on this machine. Each can call the other two, from a
conversation or a script, through the wrappers in `scripts/`. One model reviewing another's
work finds what the author cannot see; three independent readings of the same branch on
2026-09-08 found nine real defects that single readings had missed.

| Tool | Binary | Models | Effort | Good at |
|---|---|---|---|---|
| Claude | `claude` | `opus`, `sonnet`, `haiku`, `fable`, or a full name | — | Reading a large diff in context; judgement about a codebase's own rules; writing the fix as well as finding it |
| Codex | `codex` | `gpt-6-astra` | `low` `medium` `high` `xhigh` (never `max`) | Adversarial probes against real code and data; exact numbers; reliable `file:line` |
| Antigravity | `agy` | `gemini-3.8-flash-high` and others (`agy models`) | in the model name for Gemini; `--effort` for the rest | Fast second opinions; implementing a task from a written plan |

**Announce at start:** "Using external-models to run <tool> for <purpose>."

[reference.md](reference.md) has each CLI's flags, its traps, and what it did on real work.

## The traps the wrappers close

1. **Codex blocks on stdin.** `codex exec` waits forever when stdin is an open pipe, which is
   what a backgrounded shell gives it. One pass hung seventeen hours.
2. **Codex writes its report only as its final message**, captured by `-o`.
3. **Antigravity stops at a plan gate** in `--mode plan`, printing "click Proceed"; the wrapper
   sends the continuation. Its prompt must also be attached to the flag, `--print="..."`.
4. **The `claude` CLI needs its own login.** A desktop-app session's authentication belongs to
   the app's host, not to a child process, and the interactive `claude` shell function here
   injects a settings profile that points the CLI at another provider. `run-claude.sh` scrubs the
   inherited session variables, says exactly this when the login is missing, and takes `-S
   PROFILE.json`. See [reference.md](reference.md#claude) before relying on it.
5. **A reviewer must not share your working tree.** Every wrapper refuses to run in a
   repository's main checkout when it could edit. Give each tool a detached copy.
6. **Agents calling agents.** Each wrapper carries `EXTERNAL_MODELS_DEPTH` and refuses past two
   levels, so a loop cannot run up a bill in the background.

## Procedure

### 1. Pick the pattern

| You want | Pattern |
|---|---|
| Find what is wrong with a branch or diff before merging | **Review** (§2, §3), one tool or several in parallel |
| Check an implementation plan against its brief before code is written | **Gate**, `templates/gate.md` |
| A second reading of a design or a document | **Review** with the document as the package |
| Implement a task from a plan without touching your checkout | **Implement**, `templates/implement.md` |
| Anything else | **One-shot**: a prompt file and one wrapper call |

### 2. Build the package

```bash
scripts/review-package.sh BASE HEAD OUTDIR [--exclude PATHSPEC]... [--worktree NAME]...
```

Writes `OUTDIR/commits.txt`, `diffstat.txt`, `diff.patch` (8 lines of context; `--exclude` drops
large data files) and a detached worktree per `--worktree NAME` at `OUTDIR/wt-NAME`. Copy any
earlier reports into `OUTDIR` so a reviewer can be told which findings are already fixed. Probe
scripts go in `OUTDIR/scratch`.

### 3. Write the prompt from a template

```bash
sed -e "s|{{REVIEW_DIR}}|$OUTDIR|g" -e "s|{{SCRATCH_DIR}}|$OUTDIR/scratch|g" \
    -e "s|{{RULES_FILE}}|CLAUDE.md|g" -e "s|{{TEST_COMMAND}}|<the unit tests>|g" \
    templates/review.md > $OUTDIR/prompt.md
```

Then fill in by hand what only you know: what the change sets out to do, in a few groups; the
rules that bind; what the tool may run and what it must not touch. One prompt file serves every
tool, which is what makes the readings comparable.

### 4. Launch, in the background

Run each wrapper as a background command with a long timeout; each caps its own wall clock.

```bash
scripts/run-codex.sh  -p $OUTDIR/prompt.md -o $OUTDIR/report-codex.md  -C $OUTDIR/wt-codex  -e xhigh -t 90
scripts/run-agy.sh    -p $OUTDIR/prompt.md -o $OUTDIR/report-gemini.md -C $OUTDIR/wt-gemini -m gemini-3.8-flash-high -t 60
scripts/run-claude.sh -p $OUTDIR/prompt.md -o $OUTDIR/report-claude.md -C $OUTDIR/wt-claude -m opus -t 60
```

Each prints its report at the end and saves it to `-o`. **From a Claude Code session, dispatch a
subagent rather than `run-claude.sh`**: a subagent inherits the session's authentication and
reports into the conversation. The Claude wrapper is for Codex, Antigravity, a script or a cron
job, and it needs the CLI to be logged in (`claude /login` once in a terminal).

**Implementing a task:** create a worktree on a branch (`git worktree add -b task-N DIR`), fill
`templates/implement.md`, and run `run-agy.sh --mode accept-edits -C DIR` or `run-claude.sh -C DIR`.
Review the diff afterwards; never merge unreviewed.

### 5. Check health thirty seconds in

```bash
ps -axo pid,etime,command | grep -E "[c]odex exec|[a]gy --model|[c]laude -p"
```

An empty report file is normal while a tool works. Codex streams to `REPORT.stderr`, Antigravity
to `REPORT.stdout`, Claude to `REPORT` itself.

### 6. When it finishes

Reproduce every finding against the code before fixing it: Antigravity's `file:line` references
are often wrong, and any tool can be right about a symptom and wrong about the cause. Record each
finding and its disposition, fixed or refused with a reason, in the project's own record. Then
remove the copies:

```bash
git worktree remove --force $OUTDIR/wt-codex && git worktree prune
```

## Using this from Codex or Antigravity

The same scripts and templates work unchanged. The package root holds an `AGENTS.md` stating the
procedure for an agent that does not load Claude skills, and `install.sh` writes a pointer to it
into that agent's instructions file (`~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, or a project's
own). `install.sh check` reports what is installed where.

## Timings seen

| Job | Tool | Time |
|---|---|---|
| Six-commit diff review | Codex `high` | 5 min |
| 21-commit branch review | Codex `xhigh` | 15 min, 8 findings |
| 21-commit branch review | Antigravity `gemini-3.8-flash-high` | 10 min, 5 findings |
| 21-commit branch review | Claude Opus | 21 min, 7 findings |
| Plan gate | Codex `max` | died on usage limits twice, hung once |
