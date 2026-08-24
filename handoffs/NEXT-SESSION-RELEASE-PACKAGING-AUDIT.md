# Session: Release packaging and distribution hardening

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md - in particular, Stockfish's GPLv3 license and its implications
for public distribution are already a recorded decision and risk
mitigation (repository is licensed GPLv3); this session hardens the
mechanics of building and packaging a release, it does not revisit the
licensing decision.

You have unlimited usage for this session. Do not ration effort or stop
early to save budget.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b chore/release-packaging-audit ../chessanto-release-packaging main
```

Do all your work inside `../chessanto-release-packaging`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

Read `scripts/release-build.sh` and `project.yml` first to understand
exactly what the existing release pipeline does before changing anything.
Then actually run a real Release build and packaging pass end to end
(not just Debug, which is what most sessions verify against day to day)
and find out what's actually wrong with it at real distribution scale:

- **Release build correctness**: run
  `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' -configuration Release build`
  and confirm it succeeds cleanly, with no warnings that only appear in
  Release (optimization-dependent warnings, dead-code-stripping issues).
- **Code signing and entitlements**: verify the sandbox entitlements
  (mentioned as configured in M8) actually match what the app needs at
  runtime - Stockfish's in-process execution, GRDB's SQLite file access,
  Ollama's local network access (`http://127.0.0.1:11434`), and file
  access for PGN import/export. A missing entitlement that only breaks a
  sandboxed Release build (not a Debug build run from Xcode) is exactly
  the kind of bug this session exists to catch - actually launch the
  packaged Release `.app` from Finder (not from Xcode) and exercise every
  major flow to confirm nothing silently fails under the sandbox.
- **Bundle contents and size**: confirm Stockfish, the ECO opening data,
  piece/sound assets, and (if bundled per PLAN.md's optional NNUE
  upgrade) any NNUE files are actually present in the packaged `.app` and
  not accidentally excluded, and get a real measurement of the final
  `.app` size.
- **Fresh-machine first-run**: as close as you can get to simulating a
  clean install (no prior `~/Library/Containers/com.chessanto.app/`
  state, no Ollama running), launch the packaged Release build and
  confirm onboarding, the "Ollama not installed" guidance path, and the
  Stockfish-availability check all behave correctly - this is the actual
  experience of the app's very first real user and has likely never been
  exercised end to end.
- **Database safety**: if you touch a real `~/Library/Containers/...`
  database during this work, verify its SHA-256 hash before and after
  every run the way prior sessions did, and never leave it in a modified
  state that wasn't an intentional part of a real user flow.

For every real defect found, fix it in `project.yml`,
`scripts/release-build.sh`, entitlements, or app code as appropriate -
root cause, not a workaround that only happens to pass in your own
environment.

## Non-goals

- No notarization/Apple Developer account work requiring credentials you
  don't have - if something needs an actual signing identity or
  notarization submission you can't perform, document exactly what's
  needed and why in your devlog rather than working around it with a
  weaker signing configuration.
- Don't touch Play vs Engine, Chess960, search/filter, accessibility,
  visual QA, Coach verification, or opening book quality (separate
  sessions own those).

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output. "Should work" without having actually launched the packaged
Release `.app` outside Xcode is not acceptable for this session
specifically - that's the whole point of it.

```
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' -configuration Release build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The Release build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.
Include the database SHA-256 hash check (unchanged unless an intentional
real flow touched it), the measured final `.app` size, and a description
of the actual fresh-launch walkthrough you performed.

## When done

Write `devlogs/<date>-release-packaging-audit.md` with everything you
verified, every defect found and fixed, and the exact verification
output.
Add a new `## Current state - Release packaging audit` section at the TOP
of `handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`chore/release-packaging-audit`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
