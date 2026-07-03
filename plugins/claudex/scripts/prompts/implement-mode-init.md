You are starting the claudex implement loop.

Selected task: {{TASK}}

## What to do now

1. Create and check out the feature branch: `git checkout -b {{BRANCH}}`
   (if it already exists, `git checkout {{BRANCH}}`)
2. Read TASKS.md for this task's acceptance criteria, and SPEC.md if present.
3. Display the selected task to the user and confirm it is the right one before
   writing any code.
4. Implement the task on the feature branch. Do NOT commit; when you end your
   turn the Stop hook runs a Codex review of the working-tree diff first.
5. End your turn to hand off to the review loop.

## How the loop works

- Every time you end a turn with uncommitted changes, the Stop hook fires and
  Codex reviews the diff (up to {{MAX_ROUNDS}} rounds per task).
- Material findings block you: fix them, then end your turn again.
- When Codex has no material findings, the hook walks you through the commit
  and picks the next unfinished task from TASKS.md automatically.
- To stop the loop early at any point:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/mark-done.sh {{REVIEW_ID}} --loop-complete
```

Loop ID: {{REVIEW_ID}}
