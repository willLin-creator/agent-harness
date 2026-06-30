#!/bin/bash
# ============================================================================
# Agent Development Harness — Autonomous Generate → Evaluate → Fix Loop
# ============================================================================
# A language-agnostic harness that drives a coding-agent CLI through a
# generate → evaluate → fix loop against a "sprint contract" (a markdown file
# describing what to build and how it will be tested).
#
# Usage:
#   ./scripts/harness.sh docs/sprints/my-feature.md
#   ./scripts/harness.sh docs/sprints/my-feature.md --max-iterations 5
#   ./scripts/harness.sh docs/sprints/my-feature.md --generate-only
#   ./scripts/harness.sh docs/sprints/my-feature.md --evaluate-only
#
# What it does:
#   1. Reads the sprint contract
#   2. Runs the coding agent in generate mode → builds the feature + tests
#   3. Runs the coding agent in evaluate mode → checks quality + sprint contract
#   4. If issues found → runs the coding agent in fix mode → re-evaluates
#   5. Loops until APPROVED or max iterations reached
#   6. Notifies you when done
#
# Requirements:
#   - A coding-agent CLI installed and authenticated. This harness assumes
#     Claude Code's `claude` CLI; adapt the invocations below to your agent.
#   - Run from the repo root directory
# ============================================================================

set -euo pipefail

# ── Stack-specific commands (override via environment variables) ──
# Point these at the linter / test runner / formatter for YOUR project.
# Examples: eslint . | flutter analyze | ruff check | golangci-lint run
LINT_CMD="${LINT_CMD:-echo 'set LINT_CMD to your linter, e.g. eslint . / flutter analyze / ruff check'}"
# Examples: npm test | flutter test | pytest | go test ./...
TEST_CMD="${TEST_CMD:-echo 'set TEST_CMD to your test runner'}"
# Examples: prettier --write . | dart format . | ruff format | gofmt -w .
FORMAT_CMD="${FORMAT_CMD:-echo 'set FORMAT_CMD to your formatter'}"

# Name shown in desktop notifications and banners.
HARNESS_NAME="${HARNESS_NAME:-Agent Harness}"

# Tools the coding agent is allowed to use during generate/fix/evaluate.
# Override AGENT_ALLOWED_TOOLS to grant more (e.g. code-intelligence MCP tools).
AGENT_ALLOWED_TOOLS="${AGENT_ALLOWED_TOOLS:-Read,Write,Edit,Bash,Glob,Grep}"

# ── Config ──
SPRINT_CONTRACT="${1:?Usage: ./scripts/harness.sh <sprint-contract-path>}"
MAX_ITERATIONS="${2:-3}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPRINT_DIR="$(dirname "$SPRINT_CONTRACT")"
FEATURE_SLUG="$(basename "$SPRINT_CONTRACT" .md)"
BUILD_SUMMARY="$SPRINT_DIR/${FEATURE_SLUG}-BUILD_SUMMARY.md"
EVAL_OUTPUT="$SPRINT_DIR/${FEATURE_SLUG}-EVAL_RESULT.md"
HARNESS_LOG="$SPRINT_DIR/${FEATURE_SLUG}-harness.log"

# Parse flags
GENERATE_ONLY=false
EVALUATE_ONLY=false
for arg in "$@"; do
  case $arg in
    --generate-only) GENERATE_ONLY=true ;;
    --evaluate-only) EVALUATE_ONLY=true ;;
    --max-iterations) shift; MAX_ITERATIONS="$2" ;;
  esac
done

cd "$REPO_ROOT"

# ── Helpers ──
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  echo "[$(timestamp)] $1" | tee -a "$HARNESS_LOG"
}

notify() {
  local title="$1"
  local message="$2"
  # macOS desktop notification (no-op / silently ignored on other platforms)
  osascript -e "display notification \"$message\" with title \"$HARNESS_NAME\" subtitle \"$title\"" 2>/dev/null || true
  # Also print to terminal
  echo ""
  echo "════════════════════════════════════════"
  echo "  $title"
  echo "  $message"
  echo "════════════════════════════════════════"
  echo ""
}

check_agent() {
  # Assumes Claude Code's `claude` CLI; change `claude` if your agent differs.
  if ! command -v claude &> /dev/null; then
    echo "ERROR: coding-agent CLI 'claude' not found. Install and authenticate it first."
    exit 1
  fi
}

# ── Generate ──
run_generate() {
  local iteration=$1
  log "GENERATE — iteration $iteration"

  local prompt
  local context_file
  local max_turns

  if [ "$iteration" -eq 1 ]; then
    context_file="docs/context/generate-context.md"
    max_turns=25
    prompt="Read these two files ONLY:
1. $context_file (project rules — slim version)
2. $SPRINT_CONTRACT (what to build)

Build the feature. Write tests alongside code.
When done, write $BUILD_SUMMARY with what was built, contract coverage, known gaps.

Do NOT read other project-wide docs — the sprint contract has everything you need.
Do NOT ask for confirmation — just build it."
  else
    # Fix mode — minimal context
    context_file="docs/context/fix-context.md"
    max_turns=15
    local fix_list
    fix_list=$(cat "$EVAL_OUTPUT")
    prompt="Read $context_file, then fix these issues:

$fix_list

Update $BUILD_SUMMARY with fixes applied.
Do NOT read other project-wide docs — the fix list tells you exactly what to change.
Do NOT ask for confirmation — just fix it."
  fi

  # Run the coding agent non-interactively.
  # (Claude Code flags shown; adapt to your agent's equivalent.)
  # --max-turns limits tool-call rounds (controls token burn)
  echo "$prompt" | claude --print --output-format text \
    --allowedTools "$AGENT_ALLOWED_TOOLS" \
    --max-turns "$max_turns" \
    \
    2>>"$HARNESS_LOG" || {
    log "ERROR: Generate failed"
    return 1
  }

  log "GENERATE — complete"
}

# ── Evaluate ──
run_evaluate() {
  log "EVALUATE — checking build"

  local prompt="Read these files ONLY:
1. docs/context/evaluate-context.md (evaluation rules)
2. $SPRINT_CONTRACT (testable behaviors)
3. $BUILD_SUMMARY (what generator claims it built)

Follow the passes in evaluate-context.md. Write result to $EVAL_OUTPUT.
The first line of $EVAL_OUTPUT must be APPROVED if the build passes, otherwise
list the issues to fix.
Do NOT read other project-wide docs — evaluate-context.md has everything.
Do NOT ask for confirmation."

  echo "$prompt" | claude --print --output-format text \
    --allowedTools "$AGENT_ALLOWED_TOOLS" \
    --max-turns 15 \
    \
    2>>"$HARNESS_LOG" || {
    log "ERROR: Evaluate failed"
    return 1
  }

  log "EVALUATE — complete"
}

# ── Check Result ──
check_approved() {
  if [ ! -f "$EVAL_OUTPUT" ]; then
    log "WARNING: No eval output file found"
    return 1
  fi

  if head -1 "$EVAL_OUTPUT" | grep -q "APPROVED"; then
    return 0
  else
    return 1
  fi
}

# ── Main Loop ──
main() {
  check_agent

  echo ""
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  $HARNESS_NAME"
  echo "║  Sprint: $FEATURE_SLUG"
  echo "║  Max iterations: $MAX_ITERATIONS"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # Initialize log
  echo "=== Harness started $(timestamp) ===" > "$HARNESS_LOG"
  log "Sprint contract: $SPRINT_CONTRACT"
  log "Max iterations: $MAX_ITERATIONS"

  # Verify sprint contract exists
  if [ ! -f "$SPRINT_CONTRACT" ]; then
    log "ERROR: Sprint contract not found: $SPRINT_CONTRACT"
    exit 1
  fi

  # ── Generate Only Mode ──
  if $GENERATE_ONLY; then
    run_generate 1
    notify "Generate Complete" "Build summary at $BUILD_SUMMARY"
    exit 0
  fi

  # ── Evaluate Only Mode ──
  if $EVALUATE_ONLY; then
    run_evaluate
    if check_approved; then
      notify "APPROVED" "$FEATURE_SLUG passed evaluation"
    else
      notify "Issues Found" "Fix list at $EVAL_OUTPUT"
    fi
    exit 0
  fi

  # ── Full Loop ──
  for iteration in $(seq 1 "$MAX_ITERATIONS"); do
    log "━━━ Iteration $iteration of $MAX_ITERATIONS ━━━"

    # Generate (or fix)
    run_generate "$iteration"

    # Run lint + test checks before evaluation
    log "Running lint ($LINT_CMD)..."
    eval "$LINT_CMD" 2>>"$HARNESS_LOG" || {
      log "WARNING: lint found issues — evaluator will catch them"
    }

    log "Running tests ($TEST_CMD)..."
    eval "$TEST_CMD" 2>>"$HARNESS_LOG" || {
      log "WARNING: tests had failures — evaluator will catch them"
    }

    # Evaluate
    run_evaluate

    # Check result
    if check_approved; then
      log "✅ APPROVED on iteration $iteration"
      notify "APPROVED" "$FEATURE_SLUG approved after $iteration iteration(s). Ready for your review."

      # Show summary
      echo ""
      echo "Sprint: $FEATURE_SLUG"
      echo "Iterations: $iteration"
      echo "Build summary: $BUILD_SUMMARY"
      echo "Eval result: $EVAL_OUTPUT"
      echo "Log: $HARNESS_LOG"
      echo ""
      echo "Next: review the diff and merge to main."
      exit 0
    else
      log "❌ Issues found on iteration $iteration"
      if [ "$iteration" -eq "$MAX_ITERATIONS" ]; then
        log "⚠️ Max iterations reached — escalating for manual review"
        notify "ESCALATE" "$FEATURE_SLUG failed after $MAX_ITERATIONS iterations. Manual review needed."

        echo ""
        echo "Max iterations reached. Review:"
        echo "  Fix list: $EVAL_OUTPUT"
        echo "  Build summary: $BUILD_SUMMARY"
        echo "  Log: $HARNESS_LOG"
        echo ""
        echo "Options:"
        echo "  1. Fix manually and re-run: ./scripts/harness.sh $SPRINT_CONTRACT --evaluate-only"
        echo "  2. Update the sprint contract with more detail and re-run"
        echo "  3. Merge as-is and address issues in a follow-up"
        exit 1
      else
        log "Sending fix list back to generator..."
      fi
    fi
  done
}

main
