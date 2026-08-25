# 2026-08-25 - Overnight integration session

Single-session run of `handoffs/OVERNIGHT-INTEGRATION-MASTER.md` (Phase 1 first).

## qa/edge-case-pgns (merged)

Standalone re-verify in its worktree green: build `** BUILD SUCCEEDED **`, app suite
`Test run with 211 tests in 37 suites passed`, `** TEST SUCCEEDED **`.
Merged into main; post-merge verify on main green with the same counts.
A concurrent agent session completed and pushed this merge commit mid-resolution;
independently re-verified on main afterward rather than trusting that claim.
Note: multiple autonomous sessions are active on this repo tonight (a
mobile-companion-parity branch in its own worktree). Coordination rule adopted:
fetch + status check before each merge, push immediately after, never touch
foreign worktrees. Two global `pkill Chessanto.app` hygiene rules from different
sessions can kill each other's test hosts - see the Carlsen note below.

## qa/carlsen-games (merged)

Standalone re-verify found `CarlsenQAScanTests/scanAllCarlsenArchives()` crashing
with external SIGKILL mid-run (`Test crashed with signal kill`) while all 200 other
tests passed: the scan auto-runs 9,677 cached games inside every ordinary
`xcodebuild test` once its archives dir exists, and is exactly the kind of
heavy throwaway QA machinery the master doc says must not gate merges.
Fix committed on the branch (`0ed2c60`): the scan is now opt-in via
`CARLSEN_QA_RUN_SCAN=1`. Re-verified standalone green: app suite
`Test run with 201 tests in 37 suites passed`, `** TEST SUCCEEDED **`.
Merge conflicts resolved by union, not side-taking:
- `ChessGame.init(pgn:)`: normalize first (edge-cases), route
  `requiresFallback(for:)` games straight to `PGNCompatibility.parse` (carlsen),
  then upstream-on-normalized, then compat fallback.
- `parseSAN` tail: delegate upstream with the normalized token, retry the
  suffix-stripped form when different (carlsen).
Post-merge verify on main: ChessCore `84 tests`, app suite
`Test run with 212 tests in 38 suites passed`, `** BUILD SUCCEEDED **`,
`** TEST SUCCEEDED **`. Pushed as `75b4cc0`.
