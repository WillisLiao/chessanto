# 2026-08-24 - Roadmap integration into main

## What this session did

Fast-forward merged `codex/roadmap-completion` (tip `7dce456`) into `main` and pushed to `origin/main`, integrating all remaining scoped roadmap work from `handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md` into the canonical branch.

## What landed in this merge

The merge brought 43 files changed, 4775 insertions, 128 deletions, covering every scoped task that had a bootstrap document:

- **P4.2 fork detection** (`fork-detector-p4.2` branch, 6 commits).
  `ChessGame.attackedEnemySquares(from:in:)` and `ForkFact`/`ForkTarget` types, with detector, FactAuditor wiring, ReportText sentence, and 55-ply fixture scan producing zero false fires.
- **P4.2 move-quality flags** (`move-quality-p4.2` branch, 6 commits).
  `MoveQualityFact` and `ThemeDetector.moveQuality(input:ply:)` covering capture, check, checkmate, piece redevelopment through fullmove 10, and early queen before fullmove 5.
  The `[%clk]` backlog claim was re-verified and confirmed false: no clock parsing exists in `ChessComKit`, `ChessCore`, `AnalysisKit`, or `App`.
- **P4.2 absolute-pin detector** (extra slice, no standalone bootstrap).
  `ChessGame.absolutePins(in:)` and `PinFact`, hand-verified against the 56-position fixture with three fires at plies 25, 29, 31.
- **P4.5 multi-ply practice** (`multiply-practice-p4.5` branch, 5 commits).
  `PracticeSessionViewModel` now plays the engine reply after the learner's move and grades the follow-up, with two-ply grading boundary fix.
- **P4.8 LLM Coach purpose** (`coach-purpose-p4.8` branch, 6 commits).
  Structured-explainer prompt telling the model to restate attached verified facts, plus a concreteness gate in `CoachChat.send()` that regenerates responses making concrete claims without an `evaluate` tool call.
  The audit repair closes the `hadEngineData` and seed-evaluation loopholes, default-closed with a tiny clarifier whitelist.

## Verification status at merge time

The branch authors ran focused and full suites before integration; their recorded results:
- ChessCore: 44 tests in 1 suite.
- AnalysisKit: 195 tests across 6 suites.
- CoachKit: 114 tests across 8 suites.
- App: 188 tests across 34 suites.
- macOS build: `** BUILD SUCCEEDED **`.
- `git diff --check`: clean.

This session independently re-ran the ChessCore suite against the merged `main` (44 tests, passed) before pushing.
A full `xcodebuild` build/test was not re-run end-to-end in this session because the from-scratch compile is slow and the branch authors had already verified it green on the same tip; the fast-forward carries their verification forward unchanged.
No source edits were made in this session - only documentation updates and the merge itself.

## What remains

The roadmap document (`handoffs/NEXT-SESSION-ANALYSIS-CORRECTNESS.md`) names four P4.2 detectors that were explicitly scoped out of every bootstrap document written for this work: skewer, discovered attack, back-rank weakness, and trapped piece.
Each was scoped out with the note "Those are separate, later sessions" in `handoffs/NEXT-SESSION-THREAT-DETECTOR.md`.
No bootstrap document exists for any of them yet, so they remain open but are not in flight.
The `[%clk]` time-per-move insight was investigated and confirmed false: no clock data is parsed today, so any time-vs-error work needs a new parser and persistence first.

The visual-only rendering items (arrival animation timing, coordinate point size, drawn annotation shapes) remain unverifiable without a composited display, unchanged from prior sessions.
The dark-mode question and the Coach model-floor question remain open product decisions.

## Commit and push

The merge is a fast-forward, so no merge commit was created.
`main` now points at `7dce456` on `origin/main`.
