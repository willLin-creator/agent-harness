#!/bin/bash
# ============================================================================
# Run Sprints — Sequential with Dependency Ordering
# ============================================================================
# Drives the harness across a set of "sprint contracts" in dependency order,
# supporting parallel steps, resume, status, and dry-run.
#
# Usage:
#   ./scripts/run-all-sprints.sh              # Run all from the first sprint
#   ./scripts/run-all-sprints.sh --next       # Run the next unfinished sprint
#   ./scripts/run-all-sprints.sh --status     # Show status of all sprints
#   ./scripts/run-all-sprints.sh --from S4    # Resume from sprint S4
#   ./scripts/run-all-sprints.sh --dry-run    # Show order without running
#
# A sprint is "done" when its BUILD_SUMMARY file exists:
#   docs/sprints/[feature]-BUILD_SUMMARY.md
#
# Configure your own sprints below:
#   - SPRINT_CONTRACTS maps a short label (S1, S2, ...) to a contract filename
#   - STEPS lists the execution order, with optional "parallel:" steps
#   - FLAT_ORDER is the serialized order used by --next and --status
# The example values below are placeholders — replace them with your project's
# sprint contracts (markdown files living in docs/sprints/).
# ============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPRINTS_DIR="$REPO_ROOT/docs/sprints"
HARNESS="$REPO_ROOT/scripts/harness.sh"
LOG_FILE="$SPRINTS_DIR/run-all.log"

# Name shown in desktop notifications.
HARNESS_NAME="${HARNESS_NAME:-Agent Harness}"

# Ordered list of all sprints (label → contract file).
# Replace these placeholder contract filenames with your own.
declare -A SPRINT_CONTRACTS=(
  [S1]="sprint-01.md"
  [S2]="sprint-02.md"
  [S3]="sprint-03.md"
  [S4]="sprint-04.md"
  [S5]="sprint-05.md"
  [S6]="sprint-06.md"
  [S7]="sprint-07.md"
  [S8]="sprint-08.md"
  [S9]="sprint-09.md"
  [S10]="sprint-10.md"
  [S11]="sprint-11.md"
  [S12]="sprint-12.md"
  [S13]="sprint-13.md"
  [S14]="sprint-14.md"
)

# Sprint execution order (respecting dependencies).
# Format: "label:contract" or "parallel:label1:contract1:label2:contract2".
# Edit to match your dependency graph.
STEPS=(
  "parallel:S1:sprint-01.md:S3:sprint-03.md"
  "S2:sprint-02.md"
  "parallel:S5:sprint-05.md:S6:sprint-06.md"
  "S4:sprint-04.md"
  "S7:sprint-07.md"
  "S8:sprint-08.md"
  "parallel:S9:sprint-09.md:S11:sprint-11.md"
  "S10:sprint-10.md"
  "parallel:S12:sprint-12.md:S13:sprint-13.md"
  "S14:sprint-14.md"
)

# Flat execution order for --next (serialized from the dependency graph).
FLAT_ORDER=(S1 S3 S2 S5 S6 S4 S7 S8 S9 S11 S10 S12 S13 S14)

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  echo "[$(timestamp)] $1" | tee -a "$LOG_FILE"
}

# Check if a sprint is done by looking for its BUILD_SUMMARY file
is_done() {
  local contract=$1
  local slug="${contract%.md}"
  [ -f "$SPRINTS_DIR/${slug}-BUILD_SUMMARY.md" ]
}

# ── --status: show all sprint statuses ──
show_status() {
  echo "Sprint Status"
  echo "══════════════════════════════════════════════"
  printf "%-5s %-28s %s\n" "ID" "Contract" "Status"
  echo "──────────────────────────────────────────────"
  for label in "${FLAT_ORDER[@]}"; do
    local contract="${SPRINT_CONTRACTS[$label]}"
    if is_done "$contract"; then
      printf "%-5s %-28s ✅ DONE\n" "$label" "$contract"
    else
      printf "%-5s %-28s ⬜ pending\n" "$label" "$contract"
    fi
  done
  echo "──────────────────────────────────────────────"
  local done_count=0
  for label in "${FLAT_ORDER[@]}"; do
    is_done "${SPRINT_CONTRACTS[$label]}" && ((done_count++)) || true
  done
  echo "$done_count / ${#FLAT_ORDER[@]} complete"
}

# ── --next: find and run the next unfinished sprint ──
run_next() {
  for label in "${FLAT_ORDER[@]}"; do
    local contract="${SPRINT_CONTRACTS[$label]}"
    if ! is_done "$contract"; then
      echo "Next sprint: $label ($contract)"
      echo ""
      run_sprint "$label" "$contract"
      return 0
    fi
  done
  echo "All sprints are done!"
  return 0
}

run_sprint() {
  local label=$1
  local contract=$2
  local contract_path="$SPRINTS_DIR/$contract"

  if [ ! -f "$contract_path" ]; then
    log "ERROR: $contract_path not found — skipping $label"
    return 1
  fi

  log "═══════════════════════════════════════"
  log "STARTING $label: $contract"
  log "═══════════════════════════════════════"

  if $DRY_RUN; then
    log "(dry run — would run: $HARNESS $contract_path)"
    return 0
  fi

  "$HARNESS" "$contract_path" 2>&1 | tee -a "$LOG_FILE"
  local exit_code=${PIPESTATUS[0]}

  if [ $exit_code -ne 0 ]; then
    log "FAILED $label (exit $exit_code) — stopping."
    log "Resume with: ./scripts/run-all-sprints.sh --from $label"
    osascript -e "display notification \"Sprint $label FAILED — check logs\" with title \"$HARNESS_NAME\"" 2>/dev/null || true
    exit $exit_code
  fi

  log "COMPLETED $label"
}

run_parallel() {
  local label1=$1
  local contract1=$2
  local label2=$3
  local contract2=$4

  # Skip if both are already done
  local skip1=false; is_done "$contract1" && skip1=true
  local skip2=false; is_done "$contract2" && skip2=true

  if $skip1 && $skip2; then
    log "Skipping $label1 + $label2 (both done)"
    return 0
  fi

  log "═══════════════════════════════════════"
  log "STARTING PARALLEL: $label1 + $label2"
  log "═══════════════════════════════════════"

  if $DRY_RUN; then
    $skip1 && log "  $label1: already done" || log "  $label1: would run"
    $skip2 && log "  $label2: already done" || log "  $label2: would run"
    return 0
  fi

  local pids=()

  if ! $skip1; then
    run_sprint "$label1" "$contract1" &
    pids+=($!)
  else
    log "  $label1: already done — skipping"
  fi

  if ! $skip2; then
    run_sprint "$label2" "$contract2" &
    pids+=($!)
  else
    log "  $label2: already done — skipping"
  fi

  local failed=false
  for pid in "${pids[@]}"; do
    wait "$pid" || failed=true
  done

  if $failed; then
    log "One or more parallel sprints failed — stopping."
    exit 1
  fi
}

# ── Parse flags ──
START_FROM=""
DRY_RUN=false
RUN_NEXT=false
SHOW_STATUS=false

for arg in "$@"; do
  case $arg in
    --from)    shift; START_FROM="$1" ;;
    --dry-run) DRY_RUN=true ;;
    --next)    RUN_NEXT=true ;;
    --status)  SHOW_STATUS=true ;;
  esac
done

# ── Dispatch ──

if $SHOW_STATUS; then
  show_status
  exit 0
fi

if $RUN_NEXT; then
  run_next
  exit 0
fi

# ── Run all (with --from support) ──

log ""
log "============================================"
log "Sprint Runner — $(timestamp)"
log "============================================"

skip=true
if [ -z "$START_FROM" ]; then
  skip=false
fi

for step in "${STEPS[@]}"; do
  if [[ "$step" == parallel:* ]]; then
    IFS=':' read -r _ label1 contract1 label2 contract2 <<< "$step"

    if $skip; then
      if [ "$START_FROM" = "$label1" ] || [ "$START_FROM" = "$label2" ]; then
        skip=false
      else
        log "Skipping $label1 + $label2 (resuming from $START_FROM)"
        continue
      fi
    fi

    run_parallel "$label1" "$contract1" "$label2" "$contract2"
  else
    IFS=':' read -r label contract <<< "$step"

    if $skip; then
      if [ "$START_FROM" = "$label" ]; then
        skip=false
      else
        log "Skipping $label (resuming from $START_FROM)"
        continue
      fi
    fi

    # Skip if already done
    if is_done "$contract"; then
      log "Skipping $label (already done)"
      continue
    fi

    run_sprint "$label" "$contract"
  fi
done

log ""
log "============================================"
log "ALL SPRINTS COMPLETE"
log "============================================"
osascript -e "display notification \"All sprints complete!\" with title \"$HARNESS_NAME\"" 2>/dev/null || true
