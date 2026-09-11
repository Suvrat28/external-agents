You are implementing one task of a written plan, on a branch in this working directory, which is a git worktree made for this task alone.

## Read first

1. `{{RULES_FILE}}`, the project's rules.
2. `{{TASK_BRIEF_PATH}}`: the task, with the exact values, code and tests to use verbatim. It is your requirements.
<!-- Add the interfaces earlier tasks produced and this one must use, and any decision the brief cannot know. -->

## How to work

- Test first: write the failing test the brief gives, run it and see it fail, implement, run it and see it pass.
- Run `{{TEST_COMMAND}}` before committing; every test must pass.
- One commit per task, on the current branch, with the message the brief gives. End the message with:

  ```
  Co-Authored-By: {{COAUTHOR}}
  ```

- Do not touch files the task does not name. Do not weaken, skip or delete an existing test. Do not push. Do not merge or rebase.
- If the brief is ambiguous or contradicts the code, stop and say so in your report rather than guessing.

## Report

Write `{{REPORT_PATH}}` and make it your final message: status (DONE, DONE_WITH_CONCERNS, NEEDS_CONTEXT or BLOCKED), the commits made, the test command run and its summary line, and any concern or deviation from the brief, stated plainly.
