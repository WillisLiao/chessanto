# Session: Chess960 - core rules and import

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: Chess960 is currently listed as explicitly out of scope for v1 in
PLAN.md's "Out of scope for v1" section. That decision has been
overridden for this batch of work - build it - but do not otherwise
re-litigate anything else under "Product decisions (already made)".

Chess960 (Fischer Random Chess): the back-rank pieces start in one of 960
randomized-but-mirrored arrangements instead of the standard setup
(bishops on opposite colors, king strictly between the two rooks), with
castling rules adapted so the king and rook end up on their normal
castled squares (g1/f1 or c1/d1, mirrored for Black) regardless of where
they started. The point is to make the opening position itself unfamiliar
so the game can't be won by opening memorization.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/chess960-core ../chessanto-chess960-core main
```

Do all your work inside `../chessanto-chess960-core`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Rules and import layer only - no UI.

- Starting-position generation for all 960 valid arrangements: bishops on
  opposite colors, king strictly between the two rooks, knights and queen
  filling the remaining squares. Implement this as a pure, seedable
  generator (given an index 0-959, or a random seed, produce the
  deterministic back-rank arrangement) so it's testable without
  randomness.
- FEN generation and parsing for 960 starting positions, including
  castling-rights notation - standard FEN castling fields (`KQkq`) are
  ambiguous when rooks aren't on their standard files; check whether
  Shredder-FEN (file-letter castling rights, e.g. `HAha`) is needed and
  whether the underlying `chesskit-swift` dependency (wrapped by
  `Packages/ChessCore`) already has support to build on, the same way you
  would check before adding a compatibility layer.
- Castling legality for non-standard king/rook starting squares. First
  check what `chesskit-swift` already handles versus what genuinely needs
  a compatibility layer in `ChessCore` - see
  `Packages/ChessCore/Sources/ChessCore/PGNCompatibility.swift` for the
  existing pattern of "trust upstream, add a narrow fallback only where
  it's actually wrong."
- PGN import/export must correctly round-trip the `[Variant "Chess960"]`
  and `[SetUp "1"]`/`[FEN "..."]` headers, matching how real Chess960
  PGNs from chess.com/Lichess are structured.
- The existing opening book (ECO database) assumes the standard starting
  position and must not fire for Chess960 games - confirm it's actually
  silent (no wrong-opening-name output) rather than assuming it degrades
  gracefully.

## Non-goals

- No UI, no board-setup screen (a sibling session,
  `handoffs/NEXT-SESSION-CHESS960-APP-INTEGRATION.md`, owns that).
- Don't touch Play vs Engine (separate sibling sessions own that).
- Don't touch the report/analysis pipeline beyond confirming
  (Non-goal boundary: verifying is fine, changing it belongs to the
  integration session unless something in ChessCore itself is broken for
  960 positions).

## Handoff to the integration session

Write the exact public API you expose (how to generate a starting
position/FEN, how a `ChessGame` is constructed from a 960 start, what a
960 `GameRecord` looks like if anything about persistence needed to
change) explicitly at the top of your devlog.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/ChessCore
swift test --package-path Packages/AnalysisKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.
Include tests that: generate all 960 positions and verify the
bishop-color and king-between-rooks invariants hold for every one, round
trip FEN for several real 960 starting positions, and verify castling
legality/notation against at least one real Chess960 game PGN (Lichess
and chess.com both allow public PGN export of Chess960 games).

## When done

Write `devlogs/<date>-chess960-core.md` describing what you built and the
exact verification output.
Add a new `## Current state - Chess960 core` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/chess960-core`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
