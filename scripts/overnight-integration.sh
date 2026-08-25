#!/bin/bash
# Overnight integration driver.
#
# Runs one small, stateless opencode invocation per branch/phase instead of
# one giant multi-hour session. This is the actual fix for the failure mode
# from the previous run: a single long-lived agent session accumulates raw
# xcodebuild/test output in its own context for hours, which is both how it
# silently stalled (context bloat degrades instruction-following - it even
# forgot the "stay on main" rule) and why nothing showed up in git until
# morning. Splitting into one process per unit of work means:
#   - each step starts with a small, fresh context and re-derives state from
#     git + the docs, not from memory of the last step
#   - a hard OS-level `timeout` kills a stuck step automatically, instead of
#     hoping the model polices its own retry-limit rule
#   - a timeout on one branch only costs that branch, not the whole night
#
# Usage: scripts/overnight-integration.sh
# Tune the timeouts below if branches are consistently timing out or
# finishing with room to spare.

set -u
cd "$(dirname "$0")/.."
REPO="$(pwd)"

MODEL="opencode-go/ox-alpha-free"
VARIANT="max"
BRANCH_TIMEOUT="${BRANCH_TIMEOUT:-2700}"   # 45 min per branch merge
PHASE2_TIMEOUT="${PHASE2_TIMEOUT:-5400}"   # 90 min for perf-hardening / release audit
PHASE3_TIMEOUT="${PHASE3_TIMEOUT:-3600}"   # 60 min per polish-sweep round
PHASE3_ROUNDS="${PHASE3_ROUNDS:-6}"        # how many polish rounds to attempt

LOG="$REPO/overnight-integration.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"
}

kill_app() {
  pkill -9 -f "Chessanto.app/Contents/MacOS" 2>/dev/null || true
}

note_blocked() {
  local what="$1"
  local why="$2"
  cd "$REPO"
  {
    echo ""
    echo "## Blocked (overnight driver) - $what"
    echo ""
    echo "$why"
    echo "Recorded by scripts/overnight-integration.sh at $(date)."
  } >> handoffs/HANDOFF.md
  git add handoffs/HANDOFF.md
  git commit -m "Record blocked step: $what" >/dev/null 2>&1 || true
  git push origin main >/dev/null 2>&1 || true
}

# Runs one opencode invocation, piping its own output through `tail` so the
# terminal log doesn't balloon either, and enforcing a hard timeout.
run_step() {
  local label="$1"
  local prompt="$2"
  local step_timeout="$3"

  log "=== START: $label (timeout ${step_timeout}s) ==="
  kill_app

  timeout "$step_timeout" opencode run \
    --model "$MODEL" \
    --variant "$VARIANT" \
    --auto \
    "$prompt" 2>&1 | tail -c 200000 | tee -a "$LOG" >/dev/null
  local status=${PIPESTATUS[0]}

  kill_app

  if [ "$status" -eq 124 ]; then
    log "=== TIMEOUT: $label ==="
    note_blocked "$label" "Step timed out after ${step_timeout}s. Check for a stuck build/test loop or a merge conflict it couldn't resolve. Re-run this one step manually, or hand it to a fresh session directly."
  elif [ "$status" -ne 0 ]; then
    log "=== NONZERO EXIT ($status): $label ==="
    note_blocked "$label" "Step exited with status $status (not a timeout). Check overnight-integration.log around this timestamp for the actual error."
  else
    log "=== DONE: $label ==="
  fi

  cd "$REPO"
  git log --oneline -3 | tee -a "$LOG"
  echo "" | tee -a "$LOG"
}

log "############ Overnight integration run starting ############"
log "Model: $MODEL / variant $VARIANT"

# --- Phase 1: one branch per invocation --------------------------------

BRANCHES=(
  "qa/edge-case-pgns"
  "qa/carlsen-games"
  "feature/chess960-core"
  "feature/play-vs-engine-core"
  "qa/hikaru-games"
  "qa/caruana-games"
  "feature/chess960-app-integration"
  "feature/play-vs-engine-ui"
  "feature/library-search-filter"
  "feature/accessibility-matrix"
  "qa/visual-pass"
  "qa/coach-real-model-verification"
  "feature/opening-book-quality"
)

for branch in "${BRANCHES[@]}"; do
  # Skip if already merged (branch is an ancestor of main - nothing to do).
  if git merge-base --is-ancestor "$branch" main 2>/dev/null; then
    log "Skipping $branch: already merged into main."
    continue
  fi

  prompt="Read handoffs/OVERNIGHT-INTEGRATION-MASTER.md in $REPO for the full safety rules and verification bar - follow them all. But this run, do ONLY the merge for branch '$branch' (Phase 1 of that doc): re-verify it standalone in its worktree, merge it into main with conflict resolution per the doc's guidance, re-verify on main, commit, and push origin main. Do not touch any other branch this run. Do not start Phase 2 or Phase 3. When this one branch is merged and pushed (or you've determined it's genuinely blocked and recorded why in handoffs/HANDOFF.md), stop."

  run_step "merge $branch" "$prompt" "$BRANCH_TIMEOUT"
done

# --- Phase 2: performance hardening, then release packaging audit ------

run_step "performance hardening" \
  "Read handoffs/OVERNIGHT-INTEGRATION-MASTER.md in $REPO for the full safety rules and verification bar, and handoffs/NEXT-SESSION-PERFORMANCE-HARDENING-RESUME.md for the specific task. Do Phase 2 item 1 only: finish the performance hardening branch, merge it into main, commit and push. Do not start the release packaging audit or Phase 3 this run." \
  "$PHASE2_TIMEOUT"

run_step "release packaging audit" \
  "Read handoffs/OVERNIGHT-INTEGRATION-MASTER.md in $REPO for the full safety rules and verification bar, and handoffs/NEXT-SESSION-RELEASE-PACKAGING-AUDIT.md for the specific task. Do Phase 2 item 2 only: complete the release packaging audit, merge it into main, commit and push. Do not start Phase 3 this run." \
  "$PHASE2_TIMEOUT"

# --- Phase 3: bounded polish rounds -------------------------------------

for i in $(seq 1 "$PHASE3_ROUNDS"); do
  run_step "polish sweep round $i/$PHASE3_ROUNDS" \
    "Read handoffs/OVERNIGHT-INTEGRATION-MASTER.md in $REPO for the full safety rules and verification bar. Do ONE bounded round of Phase 3 (the roadmap sweep): find real, concrete issues (documentation truth, cross-feature seams, anything broken or unpolished), fix what you can verify within this run, commit and push. Do not try to do all of Phase 3 in one shot - just make real, verified, pushed progress this round, then stop." \
    "$PHASE3_TIMEOUT"
done

log "############ Overnight integration run finished ############"
log "Final state:"
git -C "$REPO" log --oneline -15 | tee -a "$LOG"
