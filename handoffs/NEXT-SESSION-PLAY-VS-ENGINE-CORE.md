# Session: Play vs Engine - core session

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Note: "playing against the engine" is currently listed as explicitly out
of scope for v1 in PLAN.md's "Out of scope for v1" section. That decision
has been overridden for this session - build it - but do not otherwise
re-litigate anything else under "Product decisions (already made)".

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b feature/play-vs-engine-core ../chessanto-play-vs-engine-core main
```

Do all your work inside `../chessanto-play-vs-engine-core`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Build the core session/state machine for a new game mode where the user
plays a full game against Stockfish via `EngineKit`, not just analysis of
an already-played game.

- Read `Packages/EngineKit` and
  `App/Sources/Chessanto/GameReplayViewModel.swift` first, to reuse the
  existing engine-session lifecycle and move-legality patterns rather
  than reinventing them. `EngineKit` already manages UCI process
  lifecycle, MultiPV parsing, and generation-counter debouncing - the
  live-game engine opponent is a new consumer of that, not a new engine
  integration.
- Design a new domain type (e.g. `LiveGameSession`) in its own file:
  the user picks a side (White/Black/random) and an engine strength.
  Map strength to Stockfish `Skill Level` (0-20) or a depth/movetime cap,
  not just a fixed movetime - a "beginner" opponent should actually play
  worse, not just slower.
- After each user move, the session asks the engine for a reply and
  applies it. The engine's move must go through the same legality path
  as everything else in ChessCore - no bypassing move validation because
  "the engine wouldn't play an illegal move".
- The session detects game end: checkmate, stalemate, draw by repetition
  or the fifty-move rule, insufficient material, and user resignation.
- On completion, persist the finished game as a normal `GameRecord`
  through the existing `Persistence` package, so it flows into the exact
  same analysis and report pipeline as every other imported game. Do not
  build a separate "played vs engine" report path - if the existing
  pipeline can't handle something about an engine game, fix the pipeline,
  don't fork it.

## Non-goals

- No UI in this session. A sibling session
  (`handoffs/NEXT-SESSION-PLAY-VS-ENGINE-UI.md`) builds the screen and
  board interaction on top of the API you expose here.
- Don't touch Chess960 (separate sibling sessions own that).
- Don't touch the report/analysis pipeline's internals beyond what's
  needed to make a finished engine game persist and analyze correctly.

## Handoff to the UI session

Whatever the public API of your session type ends up being (how it's
constructed, how a caller observes state changes, how it's told the user
made a move, how it signals game-over), write it explicitly at the top of
your devlog so the UI session can build against the real shape instead of
guessing.

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Tests pass" without the command output is not acceptable.

```
swift test --package-path Packages/EngineKit
swift test --package-path Packages/ChessCore
swift test --package-path Packages/Persistence
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.
Include at least one test that plays a full session to completion against
the real engine (or a scripted stand-in if the real engine is too slow
for CI-style runs) and asserts a persisted, analyzable `GameRecord`
results.

## When done

Write `devlogs/<date>-play-vs-engine-core.md` describing the API you
built, the strength-mapping approach, and the exact verification output.
Add a new `## Current state - Play vs Engine core` section at the TOP of
`handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`feature/play-vs-engine-core`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
