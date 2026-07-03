---
description: Run an autonomous implement-and-review loop. Claude implements a task from TASKS.md, Codex reviews each diff adversarially, Claude fixes until LGTM, then commits and advances the queue.
argument-hint: '[--rounds N] [--from-tasks] <task description>'
allowed-tools: Bash, Read, Write, Edit, AskUserQuestion
---

# /claudex:implement

User argument: $ARGUMENTS

You are running the claudex implement-mode autonomous loop. The user wants you to implement a task on a feature branch, hand the diff to Codex for adversarial code review, fix findings, and repeat until Codex has nothing material left to flag (or the round budget is exhausted). Only then do you commit and advance to the next task.

## Optional flags

Parse these flags from the start of $ARGUMENTS (the script handles them; you mainly need to detect `--from-tasks`):

- `--rounds N`. Override the default max review rounds per task (3). Common picks: 3 (default), 5 (deeper review for risky changes).
- `--from-tasks`. Pull the next unfinished task from `TASKS.md` in the project root instead of taking an inline task description. TASKS.md must exist and contain at least one `### T<num>` heading without a ✓ marker. Do not combine with an inline task; it is one or the other.

## Procedure

### 1. Empty arguments → ask for a task

If $ARGUMENTS is empty (no task, no flags), do NOT run start-loop.sh. Instead, ask the user a single question:

> What task should I implement? (e.g. "T2.3 Add rate limiting middleware", or describe the change inline)
>
> Optional: prefix with `--rounds N` to override the default of 3 review rounds per task, or pass `--from-tasks` to pull the next unfinished task from TASKS.md.

Wait for their reply, then re-invoke `/claudex:implement <their answer>`. Do not proceed past this step until you have a task or `--from-tasks`.

### 2. Identify the selected task

- **With `--from-tasks`:** read `TASKS.md` in the project root and find the first `### T<num>` heading whose line does NOT contain ✓. That is the selected task. If TASKS.md is missing or every task carries a ✓, tell the user plainly and stop; do not run start-loop.sh.
- **Without `--from-tasks`:** the selected task is everything in $ARGUMENTS that isn't a recognized flag.

### 3. Confirm the selected task before looping

Per SPEC.md, display the selected task and confirm before starting the loop (a wrong pick here wastes the whole loop). Use the AskUserQuestion tool:

- **Question:** "Start the implement loop on this task? — <selected task>"
- **Header:** "Task"
- **Options:**
  1. Label: "Yes, start the loop (Recommended)", Description: "Implement this task on a fresh claudex/implement-* feature branch. Codex reviews every diff before anything is committed."
  2. Label: "No, different task", Description: "Cancel. I'll re-run /claudex:implement with the right task (or fix TASKS.md ordering first)."

If the user picks "No, different task", stop without running start-loop.sh.

### 4. Launch the loop

Run start-loop.sh. **CRITICAL: an inline task MUST be passed as a single double-quoted string.** Task descriptions often contain apostrophes (`fix the user's session bug`) or other shell metacharacters. If you pass `$ARGUMENTS` raw, bash will see the apostrophe as an unterminated single-quoted string and fail with `unmatched '`.

Compose the bash command this way:

1. Identify any flags from `$ARGUMENTS`: `--rounds N`, `--from-tasks`.
2. Identify the task: everything that isn't a recognized flag (empty when using `--from-tasks`).
3. Pass flags as-is (no quoting needed). Pass the inline task as ONE double-quoted argument.

```bash
# Inline task, always double-quoted:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" implement [flags] "<task>"

# Examples:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" implement "T2.3 Add rate limiting middleware"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" implement --rounds 5 "fix the tokenizer's off-by-one on empty input"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" implement --from-tasks
bash "${CLAUDE_PLUGIN_ROOT}/scripts/start-loop.sh" implement --rounds 5 --from-tasks
```

If the task itself contains a literal double quote, escape it with `\"` inside the double-quoted argument. Single quotes / apostrophes inside the double-quoted task are safe and need no escaping.

The script writes the initial implement-mode state (mode, phase, task, round, branch, task counters) and prints initial instructions for you. Read them carefully.

### 5. Follow the printed instructions

- Create and check out the feature branch the script names (`claudex/implement-<session_id>`).
- Read TASKS.md for the task's acceptance criteria, and SPEC.md if present.
- Implement the task on the feature branch.
- Do NOT commit. The Stop hook runs a Codex review of the working-tree diff first; you commit only after the review comes back with no material findings.

### 6. End your turn

The Stop hook fires automatically and starts the adversarial review loop: review → fix → re-review per task, commit on LGTM, then the next unfinished task from TASKS.md until the queue is empty.

## Examples

```
/claudex:implement T2.3 Add rate limiting middleware
/claudex:implement --rounds 5 add retry logic to the webhook sender
/claudex:implement --from-tasks
/claudex:implement --rounds 5 --from-tasks
```

## Important

- Once the loop starts, do not invoke `/claudex:implement`, `/claudex:plan`, or `/claudex:review` again until the current loop finishes. The system will refuse a second concurrent loop.
- Commits land on the local feature branch only. Nothing is pushed.
- To watch state mid-loop: `/claudex:status`
- To abort an active loop: `/claudex:cancel`
- To force-clean stale state: `/claudex:rollback`
