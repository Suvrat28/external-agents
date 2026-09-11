# Reference: the three CLIs

## Codex (`~/.local/bin/codex`, 0.153.x)

```
codex exec [OPTIONS] [PROMPT]
  -m, --model MODEL                       gpt-6-astra
  -c model_reasoning_effort="EFFORT"      low | medium | high | xhigh | max   (max: usage limits kill it; xhigh finishes)
  -s, --sandbox MODE                      read-only | workspace-write | danger-full-access
  -C, --cd DIR                            working root (use a detached worktree)
  -o, --output-last-message FILE          the agent's FINAL message, verbatim
  --json                                  events as JSONL on stdout
codex exec review [--base BRANCH | --commit SHA | --uncommitted] [PROMPT]   built-in review flow; less controllable than a prompt
codex exec resume --last                 continue the previous session
```

- `~/.codex/config.toml` sets `approval_policy = "never"`: it acts without pausing. Fine in
  `read-only`; never give it `danger-full-access` on a checkout that matters.
- Always `< /dev/null`. Always a watchdog: `perl -e 'alarm SECONDS; exec @ARGV' -- codex ...`
  (macOS has no `timeout`).
- Its transcript streams to stderr; stdout stays empty until the end. A 400 KB stderr after ten
  minutes is normal.
- Ask for a fixed report format and say "your FINAL message is the report". It follows that.
- It mutates real code against real data in probes and reports exact numbers; its `file:line`
  references were correct in every case checked.
- Usage limits: when a run dies with "try again at ...", ask the user whether the window is
  clear before relaunching. Check `pgrep -f "codex exec"` first; never run two on one store.

## Antigravity (`~/.local/bin/agy`)

```
agy --print="PROMPT" [--model MODEL] [--effort low|medium|high] [--mode plan|accept-edits]
    [--dangerously-skip-permissions] [--print-timeout 60m] [--output-format text|json|stream-json]
agy --continue --print="..."             continue the most recent conversation
agy models                               list models
```

- The prompt must be attached to the flag: `--print="..."`. Given as a bare argument after
  other flags it is swallowed ("--print took --model as its prompt").
- `--mode plan` makes it analyse and then stop with "Please review the plan and click
  Proceed"; its analysis is in `~/.gemini/antigravity-cli/brain/<id>/plan.md`. The wrapper's
  `--continue` step ("Proceed. Do not write any file; print the complete final report")
  gets the report. Without `--mode`, it may edit files: only ever run it on a disposable
  worktree and forbid edits in the prompt.
- In `--mode plan` it cannot write the report file even outside the repository; capture stdout.
- Its `file:line` references are frequently fabricated (a 400-line file cited at line 1483).
  The substance was right in every case checked; verify the location yourself.
- `--dangerously-skip-permissions` is needed in print mode or tool calls wait for approval.
- A Gemini model name carries its effort (`gemini-3.8-flash-high`); `--effort low` beside it is
  refused as a conflict. Pass `--effort` only with models whose name carries none
  (`claude-opus-4-6-thinking`, `claude-sonnet-4-6`). The wrapper handles this.

## Prompts that work

- Say what the work is in four or five groups, where the package lives, which earlier reports
  are attached and that their findings are already fixed (verify, do not re-report).
- Name the rules file and the specific rules to judge against.
- Say what it may run (the unit tests, with the command) and what it must not (tests that
  write to a shared store, the network, any edit or commit).
- Fix the output format: Verdict; Findings numbered, most severe first, each with severity,
  `file:line`, the concrete probe or sequence, what goes wrong, a suggested fix; Verified;
  Not checked. Cap the length.
- Give a scratch directory outside the repository for probe scripts.

## What to do with a report

Every finding is verified against the code before it is acted on. Fixed findings get a test
that reproduces the probe. Refused findings get a written reason. Both go into the project's
validation record, with the tool, model, effort, date and how long it ran. A finding that
would change a decision is the user's call, not the reviewer's.

## Claude (`claude`, 2.1.x) <a id="claude"></a>

**Authentication, checked on this machine 2026-09-08.** The CLI had no credentials of its own:
no `~/.claude/.credentials.json`, nothing in the login keychain, so `claude -p` answered
"Not logged in · Please run /login" even with the host session's variables scrubbed. A Claude
Code session running under the desktop app is authenticated by the app's host, and a child
process does not inherit that. To make `run-claude.sh` usable as Claude, run `claude /login`
once in a terminal, or export an `ANTHROPIC_API_KEY`. Until then it works only with `-S
PROFILE.json`, and `~/.claude/profiles/deepseek.json` is a profile whose `ANTHROPIC_BASE_URL`
points the CLI at DeepSeek — useful, but not Claude.

```
claude -p "PROMPT" [--model opus|sonnet|haiku|fable|<full name>]
       [--permission-mode acceptEdits|auto|bypassPermissions|manual|dontAsk|plan]
       [--output-format text|json|stream-json] [--settings FILE] [--add-dir DIR]
       [--allowedTools ...] [--append-system-prompt ...] [--agents JSON] [--resume ID]
```

- **`claude` in an interactive zsh here is a shell function** that injects
  `--settings $CLAUDE_DEEPSEEK_SETTINGS` (`~/.claude/profiles/deepseek.json`). A `#!/bin/bash`
  script does not see the function and runs the binary at `~/.local/bin/claude` with no profile,
  which is why the wrapper needs the CLI's own login; pass `-S FILE` to apply a profile on purpose.
- The wrapper scrubs `ANTHROPIC_BASE_URL` and the `CLAUDE_CODE_*` session variables before
  spawning: they name the caller's socket, token and endpoint, and the child is not that session.
- `--permission-mode bypassPermissions` is the wrapper's default, matching the posture the other
  two run in; it is why the wrapper refuses a main checkout. `plan` is the read-only mode, but it
  answers with a plan rather than a report, so prefer a disposable worktree over `plan` for reviews.
- It reads the repository's own `CLAUDE.md` and skills, which is the point: it judges a codebase
  against that codebase's rules without being told them. Codex and Antigravity need the rules
  named in the prompt.
- From inside a Claude Code session, a subagent (the `Agent` tool, `model: "opus"`,
  `run_in_background: true`) is better than this wrapper: it reports into the conversation and
  costs no extra process. Use the wrapper from Codex, Antigravity, a script or a cron job.
- Long jobs: `--output-format stream-json` gives progress; plain `text` gives the final answer only.

## Cross-calling

Every wrapper exports `EXTERNAL_MODELS_DEPTH` and refuses at 2, so Claude can call Codex which
can call Claude, and no further. Each also refuses a repository's main checkout whenever the run
could edit it; give a detached worktree. Neither guard has a quiet override: `--allow-main`
(Claude) is explicit, and depth cannot be overridden at all.
