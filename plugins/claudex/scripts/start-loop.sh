#!/usr/bin/env bash
# Claudex start-loop.sh
#
# Called by the /claudex slash command. Sets up state for a fresh loop and
# prints initial instructions for Claude to read.
#
# Usage:
#   bash start-loop.sh plan "<topic>"
#   bash start-loop.sh review
#   bash start-loop.sh implement "<task description>"
#   bash start-loop.sh implement --from-tasks
#
# Exit codes:
#   0  ok, instructions printed to stdout
#   1  another loop is already active in this project
#   2  invalid mode argument
#   3  internal error (state write failed)

set +e

CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# shellcheck source=/dev/null
source "$CLAUDE_PLUGIN_ROOT/scripts/state-helpers.sh"

MODE="$1"
shift || true

# Parse optional flags before the topic. Recognized flags:
#   --rounds N         override default max rounds (positive integer)
#   --from-draft       use existing PLAN.md instead of drafting from scratch (plan mode only)
#   --from-tasks       pull the next unfinished task from TASKS.md instead of an inline
#                      task argument (implement mode only)
#   --skip-interview   skip the topic-sharpening interview offer (consumed by the slash
#                      command; accepted here as a no-op so it's safe to pass through)
#   --interviewed      marker passed by the slash command after a successful interview;
#                      records interview_used=true in state for status/audit
FROM_DRAFT=false
FROM_TASKS=false
CUSTOM_ROUNDS=""
INTERVIEW_USED=false
while [ $# -gt 0 ]; do
  case "$1" in
    --rounds)
      shift
      CUSTOM_ROUNDS="$1"
      shift || true
      ;;
    --rounds=*)
      CUSTOM_ROUNDS="${1#--rounds=}"
      shift
      ;;
    --from-draft)
      FROM_DRAFT=true
      shift
      ;;
    --from-tasks)
      FROM_TASKS=true
      shift
      ;;
    --skip-interview)
      shift
      ;;
    --interviewed)
      INTERVIEW_USED=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

TOPIC="$*"

if [ -z "$MODE" ]; then
  echo "Usage: start-loop.sh plan [--rounds N] [--from-draft] <topic> | start-loop.sh review [--rounds N] | start-loop.sh implement [--rounds N] (--from-tasks | <task description>)" >&2
  exit 2
fi

# Validate --rounds.
if [ -n "$CUSTOM_ROUNDS" ]; then
  if ! echo "$CUSTOM_ROUNDS" | grep -qE '^[1-9][0-9]*$'; then
    echo "--rounds must be a positive integer (got: $CUSTOM_ROUNDS)" >&2
    exit 2
  fi
fi

# Validate --from-draft (plan mode only, requires PLAN.md to exist).
if [ "$FROM_DRAFT" = "true" ]; then
  if [ "$MODE" != "plan" ]; then
    echo "--from-draft only applies to plan mode, not $MODE" >&2
    exit 2
  fi
  if [ ! -f "PLAN.md" ] || [ ! -s "PLAN.md" ]; then
    echo "--from-draft requires PLAN.md to exist in the project root and be non-empty." >&2
    echo "Either remove --from-draft (let Claude draft from scratch) or create PLAN.md first." >&2
    exit 2
  fi
fi

# Validate --from-tasks (implement mode only).
if [ "$FROM_TASKS" = "true" ] && [ "$MODE" != "implement" ]; then
  echo "--from-tasks only applies to implement mode, not $MODE" >&2
  exit 2
fi

# Next unfinished task heading in TASKS.md ("### T1.2 Title" -> "T1.2 Title").
# Same convention as the stop hook: a task is finished when its heading
# contains the completion marker "✓".
next_unfinished_task() {
  [ -f "TASKS.md" ] || return 1
  grep -E '^###[[:space:]]+T[0-9]' TASKS.md 2>/dev/null \
    | grep -v '✓' | head -1 | sed -E 's/^###[[:space:]]+//'
}

unfinished_task_count() {
  if [ ! -f "TASKS.md" ]; then
    echo 0
    return 0
  fi
  local n
  n=$(grep -E '^###[[:space:]]+T[0-9]' TASKS.md 2>/dev/null | grep -cv '✓' 2>/dev/null)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  echo "$n"
}

TASK=""
case "$MODE" in
  plan)
    if [ -z "$TOPIC" ]; then
      echo "Plan mode requires a topic. Usage: start-loop.sh plan <topic>" >&2
      exit 2
    fi
    ;;
  review)
    ;;
  implement)
    if [ "$FROM_TASKS" = "true" ]; then
      if [ -n "$TOPIC" ]; then
        echo "Provide either an inline task or --from-tasks, not both." >&2
        exit 2
      fi
      if [ ! -f "TASKS.md" ] || [ ! -s "TASKS.md" ]; then
        echo "--from-tasks requires TASKS.md to exist in the project root and be non-empty." >&2
        exit 2
      fi
      TASK=$(next_unfinished_task)
      if [ -z "$TASK" ]; then
        echo "No unfinished tasks in TASKS.md (every task heading carries a ✓)." >&2
        echo "Add a task or pass an inline task description instead of --from-tasks." >&2
        exit 2
      fi
      TOPIC="$TASK"
    else
      if [ -z "$TOPIC" ]; then
        echo "Implement mode requires a task description or --from-tasks. Usage: start-loop.sh implement (--from-tasks | <task description>)" >&2
        exit 2
      fi
      TASK="$TOPIC"
    fi
    ;;
  *)
    echo "Unknown mode: $MODE. Use plan, review, or implement." >&2
    exit 2
    ;;
esac

mkdir -p "$CLAUDEX_STATE_DIR" || exit 3

# Sweep stale loops first (anything older than 15 min by default).
claudex_sweep_stale

# Refuse to start if another loop is genuinely active.
# State files are kept on disk for audit even after a loop completes or is
# cancelled, so we check the phase to decide if a loop is still running.
# Active phases: drafting, reviewing, revising. Terminal: done, cancelled, errored.
for state in "$CLAUDEX_STATE_DIR"/*.state; do
  [ -f "$state" ] || continue
  state_phase=$(claudex_state_read_field "$state" "phase")
  case "$state_phase" in
    done|cancelled|errored|"")
      # Terminal phase or unparseable; not an active loop.
      ;;
    *)
      active_id=$(basename "$state" .state)
      echo "Another claudex loop is already active: $active_id (phase: $state_phase)" >&2
      echo "Run /claudex:cancel to abort it, or /claudex:rollback to force-clean." >&2
      exit 1
      ;;
  esac
done

# Generate review_id.
REVIEW_ID="$(claudex_new_review_id)"
if ! claudex_validate_review_id "$REVIEW_ID"; then
  echo "Failed to generate valid review_id." >&2
  exit 3
fi

STATE_FILE="$CLAUDEX_STATE_DIR/$REVIEW_ID.state"
LOCK_FILE="$CLAUDEX_STATE_DIR/$REVIEW_ID.lock"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW_EPOCH="$(date -u +%s)"
REPO_ROOT="$(pwd)"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
MAX_PLAN_ROUNDS="${CLAUDEX_MAX_PLAN_ROUNDS:-3}"
MAX_REVIEW_ROUNDS="${CLAUDEX_MAX_REVIEW_ROUNDS:-3}"
MAX_IMPLEMENT_ROUNDS="${CLAUDEX_MAX_IMPLEMENT_ROUNDS:-3}"

if [ "$MODE" = "plan" ]; then
  MAX_ROUNDS="$MAX_PLAN_ROUNDS"
  PHASE="drafting"
elif [ "$MODE" = "implement" ]; then
  MAX_ROUNDS="$MAX_IMPLEMENT_ROUNDS"
  PHASE="implementing"
else
  MAX_ROUNDS="$MAX_REVIEW_ROUNDS"
  PHASE="reviewing"
fi

# --rounds flag overrides default max.
if [ -n "$CUSTOM_ROUNDS" ]; then
  MAX_ROUNDS="$CUSTOM_ROUNDS"
fi

# Escape topic for YAML (basic; topic is user-provided).
# The interview path can produce a multi-line topic ("Scope: ...\nConstraints: ...");
# the state file's grep+sed reader only keeps the first line, so collapse any
# embedded newlines/CRs into "; " before escaping quotes. Codex still gets a
# readable summary on a single line.
ESCAPED_TOPIC="$(printf '%s' "$TOPIC" | tr '\n\r' '  ' | sed -e 's/  */ /g' -e 's/"/\\"/g')"

if [ "$MODE" = "implement" ]; then
  # Implement-mode state carries the extra fields the stop hook's implement
  # branch reads: task, current_branch, tasks_completed, tasks_remaining.
  # Same format, same helpers, just more fields.
  ESCAPED_TASK="$(printf '%s' "$TASK" | tr '\n\r' '  ' | sed -e 's/  */ /g' -e 's/"/\\"/g')"

  # Branch naming per SPEC.md: claudex/implement-<session_id>. When Claude
  # Code doesn't expose a session id (e.g. tests), fall back to the review_id
  # so branch names stay unique (ARCHITECTURE.md's example uses this form).
  BRANCH_SUFFIX="$SESSION_ID"
  if [ -z "$BRANCH_SUFFIX" ] || [ "$BRANCH_SUFFIX" = "unknown" ]; then
    BRANCH_SUFFIX="$REVIEW_ID"
  fi
  CURRENT_BRANCH="claudex/implement-$BRANCH_SUFFIX"

  # Initial queue size. The hook recomputes this live from TASKS.md as the
  # loop advances; an inline task with no TASKS.md counts as one remaining.
  if [ -f "TASKS.md" ]; then
    TASKS_REMAINING=$(unfinished_task_count)
  else
    TASKS_REMAINING=1
  fi

  STATE_CONTENT="mode: $MODE
phase: $PHASE
topic: \"$ESCAPED_TOPIC\"
task: \"$ESCAPED_TASK\"
round: 1
max_rounds: $MAX_ROUNDS
from_tasks: $FROM_TASKS
review_id: $REVIEW_ID
repo_root: $REPO_ROOT
session_id: $SESSION_ID
started_at: $NOW
started_at_epoch: $NOW_EPOCH
last_updated_at: $NOW
current_branch: $CURRENT_BRANCH
tasks_completed: 0
tasks_remaining: $TASKS_REMAINING
decision_signal: none"
else
  STATE_CONTENT="mode: $MODE
phase: $PHASE
topic: \"$ESCAPED_TOPIC\"
round: 1
max_rounds: $MAX_ROUNDS
from_draft: $FROM_DRAFT
interview_used: $INTERVIEW_USED
review_id: $REVIEW_ID
repo_root: $REPO_ROOT
session_id: $SESSION_ID
started_at: $NOW
started_at_epoch: $NOW_EPOCH
last_updated_at: $NOW
decision_signal: none"
fi

claudex_state_write "$STATE_FILE" "$STATE_CONTENT" || exit 3
claudex_lock_write "$LOCK_FILE" || exit 3

# Print initial instructions to stdout. Claude will read these.
case "$MODE" in
  plan)
    echo "Claudex plan mode initialized."
    echo "Review ID: $REVIEW_ID"
    echo "Topic: $TOPIC"
    echo "Max rounds: $MAX_ROUNDS"
    if [ "$FROM_DRAFT" = "true" ]; then
      echo "Source: existing PLAN.md (--from-draft)"
      echo ""
      cat "$CLAUDE_PLUGIN_ROOT/scripts/prompts/plan-mode-from-draft.md" 2>/dev/null \
        | sed -e "s|{{TOPIC}}|$TOPIC|g" -e "s|{{REVIEW_ID}}|$REVIEW_ID|g" -e "s|{{MAX_ROUNDS}}|$MAX_ROUNDS|g"
    else
      echo ""
      echo "Round 1 - drafting plan."
      echo ""
      cat "$CLAUDE_PLUGIN_ROOT/scripts/prompts/plan-mode-init.md" 2>/dev/null \
        | sed -e "s|{{TOPIC}}|$TOPIC|g" -e "s|{{REVIEW_ID}}|$REVIEW_ID|g"
    fi
    ;;
  review)
    echo "Claudex review mode initialized."
    echo "Review ID: $REVIEW_ID"
    echo "Max rounds: $MAX_ROUNDS"
    echo ""
    cat "$CLAUDE_PLUGIN_ROOT/scripts/prompts/review-mode-init.md" 2>/dev/null \
      | sed -e "s|{{REVIEW_ID}}|$REVIEW_ID|g"
    ;;
  implement)
    echo "Claudex implement mode initialized."
    echo "Review ID: $REVIEW_ID"
    echo "Task: $TASK"
    if [ "$FROM_TASKS" = "true" ]; then
      echo "Source: next unfinished task in TASKS.md (--from-tasks)"
    fi
    echo "Max rounds per task: $MAX_ROUNDS"
    echo "Branch: $CURRENT_BRANCH"
    echo ""
    # T1.4 adds a prompts/implement-mode-init.md template; use it when present,
    # otherwise print the inline instructions below.
    if [ -f "$CLAUDE_PLUGIN_ROOT/scripts/prompts/implement-mode-init.md" ]; then
      sed -e "s|{{TASK}}|$TASK|g" -e "s|{{REVIEW_ID}}|$REVIEW_ID|g" \
          -e "s|{{MAX_ROUNDS}}|$MAX_ROUNDS|g" -e "s|{{BRANCH}}|$CURRENT_BRANCH|g" \
          "$CLAUDE_PLUGIN_ROOT/scripts/prompts/implement-mode-init.md" 2>/dev/null
    else
      cat <<IMPLEOF
You are starting the claudex implement loop.

Selected task: $TASK

1. Create and check out the feature branch: git checkout -b $CURRENT_BRANCH
   (if it already exists, git checkout $CURRENT_BRANCH)
2. Read TASKS.md for this task's acceptance criteria, and SPEC.md if present.
3. Display the selected task to the user and confirm it is the right one before
   writing any code.
4. Implement the task on the feature branch. Do NOT commit; when you end your
   turn the Stop hook runs a Codex review of the working-tree diff first.
5. End your turn to hand off to the review loop.
IMPLEOF
    fi
    ;;
esac

exit 0
