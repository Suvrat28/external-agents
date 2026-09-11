# external-models: running another model from this machine

You are an agent with a shell. Three model families are installed here, and you can call any of
them for a review, a plan gate, a second opinion, or a one-shot question. Use the wrappers: they
close traps that cost hours when hit directly.

    ~/.agents/skills/external-models/scripts/run-claude.sh   Claude    (opus, sonnet, haiku, fable)
    ~/.agents/skills/external-models/scripts/run-codex.sh    Codex     (gpt-6-astra)
    ~/.agents/skills/external-models/scripts/run-agy.sh      Antigravity (gemini-3.8-flash-high and others)

All three take the same shape:

    run-<tool>.sh -p PROMPT_FILE -o REPORT_FILE [-m MODEL] [-C DIR] [-t MINUTES]

`-C DIR` is the working directory: **give a disposable copy**, not your checkout —
`git worktree add --detach DIR HEAD`. The wrappers refuse a repository's main checkout when the
run could edit it. `-t` caps the wall clock in minutes. Each prints the report and saves it to
`-o`. Run them in the background; a review takes five to twenty minutes.

To review a branch:

    S=/tmp/review-$$
    ~/.agents/skills/external-models/scripts/review-package.sh main HEAD $S --worktree codex
    # write $S/prompt.md from ~/.agents/skills/external-models/templates/review.md,
    # filling {{REVIEW_DIR}}=$S, {{SCRATCH_DIR}}=$S/scratch, {{RULES_FILE}}, {{TEST_COMMAND}}
    ~/.agents/skills/external-models/scripts/run-codex.sh -p $S/prompt.md -o $S/report.md -C $S/wt-codex -e xhigh -t 90
    git worktree remove --force $S/wt-codex && git worktree prune

Templates: `templates/review.md`, `templates/gate.md`, `templates/implement.md`. Each ends in a
fixed report format, which is what makes the answers usable.

`run-claude.sh` needs the `claude` CLI to be logged in on this machine (`claude /login`, once,
in a terminal) or an `ANTHROPIC_API_KEY` exported; it says so plainly if it is not. `-S
PROFILE.json` applies a settings profile instead. Codex and Antigravity need no such setup.

Rules that matter:

- One prompt file per job, shared by every tool you ask, so the readings are comparable.
- Say in the prompt what the tool may run and what it must not touch: a shared database, the
  network, any edit or commit.
- Verify every finding against the code before acting on it. Antigravity's line numbers are
  often wrong; any tool can be right about a symptom and wrong about the cause.
- The wrappers refuse to nest more than two deep (`EXTERNAL_MODELS_DEPTH`). Do not defeat it.
- Full flags, traps and timings: `~/.agents/skills/external-models/reference.md`.
