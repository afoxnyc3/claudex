### Claudex implement review, round {{ROUND}} of {{MAX_ROUNDS}}, {{PERSONA_LABEL}}

**Task:** {{TASK}}

{{PREV_TALLY_LINE}}**Run the runner:**

```
bash {{RUNNER_SCRIPT}}
```

When Codex finishes, read the findings summary from:

`{{FINDINGS_FILE}}`

**Then decide:**

- **Material findings exist** → fix them in the code. Do NOT commit. Then end your turn; the next review round starts automatically.
- **No material findings (or only style nits)** → signal task completion:
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/mark-done.sh {{REVIEW_ID}} --task-complete
  ```
  Then end your turn. The hook will walk you through the commit.
- **To stop the entire loop instead** (wrong task, blocked, user asked to stop):
  ```
  bash ${CLAUDE_PLUGIN_ROOT}/scripts/mark-done.sh {{REVIEW_ID}} --loop-complete
  ```
  Then end your turn.

**Hard stop:** if this is round {{MAX_ROUNDS}} and Codex still has substantive findings, end your turn anyway. The hook will exit cleanly with the remaining concerns.
