### Claudex implement: task approved, commit it

Codex had no material findings on:

**Task:** {{TASK}}

Now land it:

1. Mark the task complete in TASKS.md: append ✓ to its `###` heading (e.g. `### {{TASK}} ✓`).
2. Stage the specific files you changed (never `git add -A` or `git add .`), including TASKS.md.
3. Commit to the current branch ({{BRANCH}}) with a message like `feat(T<num>): <imperative summary>`, a short body, and a `Closes T<num>` footer.
4. End your turn. The hook picks the next task from TASKS.md automatically.

Do NOT push. Local commit only.
