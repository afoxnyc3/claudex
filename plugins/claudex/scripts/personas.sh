#!/usr/bin/env bash
# Claudex Personas
#
# Source this from stop-hook.sh:
#   source "$CLAUDE_PLUGIN_ROOT/scripts/personas.sh"
#
# Provides:
#   claudex_persona_for_round <round>
#     Prints a focused reviewer-persona stanza for the given round number.
#     Round 1: skeptical senior engineer
#     Round 2: security and data-integrity reviewer
#     Round 3+: ops / SRE reviewer (deepens on later rounds)
#
#   claudex_persona_label_for_round <round>
#     Prints a one-line label for BLOCK headers (e.g. "Security review").
#
#   claudex_implement_persona_for_round <round>
#     Implement-mode variant. Same rotation, but the stanzas hunt CODE
#     defects in a working-tree diff rather than design flaws in a plan.
#     Round 1: senior engineer (logic, edge cases, error handling)
#     Round 2: security reviewer (injection, auth, secrets, races)
#     Round 3+: ops / SRE reviewer (observability, rollback, compat)
#
#   claudex_implement_persona_label_for_round <round>
#     Prints a one-line label for implement-mode BLOCK headers.

claudex_persona_label_for_round() {
  local r="${1:-1}"
  case "$r" in
    1) echo "Senior-engineer review" ;;
    2) echo "Security and data-integrity review" ;;
    *) echo "Ops and SRE review" ;;
  esac
}

claudex_persona_for_round() {
  local r="${1:-1}"
  case "$r" in
    1)
      cat <<'STANZA'
Persona: skeptical senior engineer doing the first pass.

Hunt for design flaws, broken assumptions, and ambiguous specs. Look for places where the plan glosses over hard parts, hand-waves edge cases, or solves the wrong problem. Flag anything that would obviously break under stress or that a reviewer in two weeks would call "we needed to think about this."
STANZA
      ;;
    2)
      cat <<'STANZA'
Persona: security and data-integrity reviewer doing the second pass.

Focus this round on: authentication and authorization gaps, input validation and injection, race conditions and concurrent-write hazards, partial-failure recovery and idempotency, secret handling, audit trails, and data-loss scenarios under crash or retry. Round 1 should have caught the obvious design issues; you are looking for the things that pass functional review but fail in production under adversarial or unlucky conditions.
STANZA
      ;;
    *)
      cat <<'STANZA'
Persona: operations and SRE reviewer doing a late-stage pass.

Focus this round on: rollback safety, observability and metrics, gradual rollout (feature flags, canaries), version skew between client and server, on-call ergonomics (runbooks, alerting), backwards compatibility, and capacity / blast-radius concerns. Earlier rounds should have hardened the design; you are checking that it can be deployed safely, monitored in flight, and reverted cleanly when something goes wrong. If this is a re-run of the ops persona on a later round, deepen the previous angles rather than going generic.
STANZA
      ;;
  esac
}

claudex_implement_persona_label_for_round() {
  local r="${1:-1}"
  case "$r" in
    1) echo "Senior-engineer code review" ;;
    2) echo "Security code review" ;;
    *) echo "Ops and SRE code review" ;;
  esac
}

claudex_implement_persona_for_round() {
  local r="${1:-1}"
  case "$r" in
    1)
      cat <<'STANZA'
Persona: skeptical senior engineer reviewing the diff for correctness.

You are reviewing code, not a plan. Read the actual changes and hunt for logic errors, off-by-one and boundary mistakes, unhandled edge cases (empty input, missing files, zero, negative, unicode, very large values), broken assumptions about caller behavior or data shape, and missing or swallowed error handling. Check that return values and exit codes are actually checked, that failure paths do something sane, and that the code does what the task says rather than something adjacent. Flag dead code, copy-paste slips, and any branch that can never fire or clearly fires wrong.
STANZA
      ;;
    2)
      cat <<'STANZA'
Persona: security reviewer reading the diff for exploitable code defects.

Round 1 covered logic. This round, hunt for security defects in the code itself: unvalidated or unsanitized input reaching shells, eval, SQL, paths, or interpolated strings (injection of any kind); authentication and authorization checks that are missing, bypassable, or done client-side; secrets, tokens, or credentials hardcoded, logged, or written to world-readable files; race conditions and TOCTOU windows around files, locks, and shared state; unsafe temp-file handling and predictable paths; and error messages that leak internals. Trace untrusted data from entry to sink. If input can be attacker-shaped, assume it will be.
STANZA
      ;;
    *)
      cat <<'STANZA'
Persona: operations and SRE reviewer reading the diff for deployment risk.

Earlier rounds covered logic and security. This round, hunt for code that will hurt in production: missing or misleading logging around failure paths (can an operator tell WHY it broke?), silent failures and swallowed exit codes, changes that cannot be rolled back cleanly (state-file format changes, destructive migrations, one-way renames), backward-compatibility breaks for existing state, configs, or callers of changed interfaces, and deployment hazards like new hard dependencies, platform-specific commands (GNU vs BSD), or behavior that differs between clean install and upgrade. If this is a re-run of the ops persona on a later round, deepen the previous angles against the newest diff rather than going generic.
STANZA
      ;;
  esac
}
