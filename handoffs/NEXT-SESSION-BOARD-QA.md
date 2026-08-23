# Next session - native QA of the four unverified board items

Bootstrap document for unstarted work.
Written 2026-08-24, running in parallel with `handoffs/NEXT-SESSION-THREAT-DETECTOR.md` (a separate session, separate git worktree/branch - do not read or wait on it, your work is independent).

You are working in a dedicated git worktree on branch `board-qa-verification`, checked out from `main` at commit `b5a00b4`. This is a real, separate checkout - commit and push this branch when you are done, do not attempt to merge to `main` yourself, and do not touch the primary checkout at `/Users/willis/Documents/chessanto` (a different session may be using it).

## Read first

1. `handoffs/HANDOFF.md`, in full, for current project state.
2. `devlogs/2026-07-30.md`, section "Priority 3: the board" and "Not verified in the real app" - this names exactly what has never been confirmed live and why (screen capture/compositing was refused to the agent in that environment).
3. `App/Sources/Chessanto/Board/BoardView.swift` and `App/Sources/Chessanto/Board/BoardInteraction.swift` (or wherever these files actually are - confirm exact paths, the repository has moved files between sessions before) in full, so you understand what you are verifying before you touch it.
4. `scripts/axdrag.swift`, `scripts/axclick.swift`, `scripts/axclickat.swift`, `scripts/axprobe.swift`, `scripts/capture-window.swift` - the existing native-UI-testing tooling, written specifically for this kind of verification and committed ready to run.
5. `devlogs/2026-07-19.md`'s notes on this tooling's sharp edges: `axclick.swift` needs a `--last` flag in some cases, and `axclickat.swift`'s raw-coordinate clicks were unreliable on at least one toolbar button in that session. Read the actual note before relying on either script blind.
6. `scripts/release-build.sh`.

## The problem

Across three sessions now (2026-07-30, 2026-08-21, 2026-08-22), four board behaviors have been implemented and unit-tested but **never observed running in a real, composited window**:

1. Drag and drop (a `simultaneousGesture` alongside the existing per-square tap targets, 4pt drag threshold).
2. Right-drag annotation arrows and circles (via `RightDragCatcher`, an `NSViewRepresentable` that claims hit tests only during a right-mouse event).
3. The arrival animation (a piece moving between squares - a 1-to-0 scalar animated inside the piece layer, 180ms ease-out, skipped under Reduce Motion).
4. Coordinate label sizing (22% of square size with an 11pt floor, bold weight).

Every prior attempt to verify these found that screen capture/compositing was unavailable to the agent in that session's environment. Your first job is to find out whether that is still true in yours. It may not be - environments change between sessions.

## What to do

### Step 1 - check whether you can see a composited window at all

Build the Release app with `scripts/release-build.sh`, launch it, and try `scripts/capture-window.swift` (or equivalent) against it. If you get a real screenshot back, compositing works in your environment and you can proceed with full visual verification. If every window (including the app's own menu bar) reports `onscreen=false` the way prior sessions found, say so immediately, do not spend the whole session fighting it, and fall back to accessibility-tree-only verification (`axprobe.swift`) for what can be confirmed that way (accessibility identifiers surviving, an element existing and being interactable) while explicitly reporting the visual-only items (animation timing, coordinate sizing, drawn arrows) as still unverified.

### Step 2 - native data safety, before touching the real database

This project has a standing procedure for any native QA against the real app, because the real app writes to the user's live SQLite database on launch (`~/Library/Containers/com.chessanto.app/...`):

1. Back up the live sandbox database before doing anything else.
2. Copy that backup to a disposable path.
3. Launch the built app with **both** required opt-in environment variables set: `CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE=1` and `CHESSANTO_DATABASE_PATH=<path to your disposable copy>`. Confirm both are required by reading how `GameStore`/`GameLibrary` actually consult them (search the App source for `CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE`) before assuming the exact mechanism - the doc references above name the pattern, confirm it against the real source.
4. Do all QA against the disposable copy, never the live path.
5. When finished, verify the live database is untouched (`PRAGMA integrity_check`, and compare a hash or row counts before/after if you want extra confidence) and delete the disposable copy.

Do not skip this. A prior session in this project found and fixed a real data-safety bug (`xcodebuild test` on the app scheme launching the real app as its test host and writing a migration to the live database) specifically because this procedure was being followed carefully enough to notice a modification time that shouldn't have changed - see `devlogs/2026-07-30.md`'s "A data-safety defect found while setting up QA" section for the full story.

### Step 3 - verify each of the four items, and use real interaction, not just source reading

For each of the four items:
- Reproduce it live: real clicks/drags via the AX-scripting tools or, if compositing works, real synthesized input.
- Confirm the existing 64 `square-<algebraic>` accessibility identifiers survive drag interaction (this was a stated constraint on the original drag implementation - confirm it still holds).
- For the arrival animation and coordinate sizing specifically, you need actual visual evidence (a screenshot), not an accessibility-tree read - the AX tree does not expose animation timing or a label's rendered point size.
- If you find a real bug, fix it - but stay narrowly scoped to the specific defect you found and verified live, in the same file(s) that already implement the feature. Do not redesign the board interaction system. If a bug is ambiguous or you are not confident in the root cause, report it rather than guessing at a fix (this project's standing rule: reproduce first, fix the root cause, not the symptom - see the `diagnosing-bugs` convention referenced throughout this repo's other planning documents).
- If everything works as designed, say so plainly with the evidence (screenshot paths, or the specific AX-tree reads that confirm it) rather than assuming it does.

## Required rigor

- TDD for any code fix you make (this project's standing convention) - reproduce the bug with a test or a live-interaction script first, then fix.
- Never use the em dash character ("—"); use a plain dash ("-").
- One full sentence per physical line in any long Markdown you write or substantially edit.
- Do not modify `CHANGELOG.md` or generated files.
- Do not add an agent name as a co-author in commit messages.
- Do not touch `Packages/AnalysisKit` at all - this session is exclusively about the board's interaction and rendering, not analysis.

## Validation commands

1. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build` from the repo root - must end `** BUILD SUCCEEDED **`.
2. `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test` from the repo root - must end `** TEST SUCCEEDED **`. Baseline before this session: 170 tests across 34 suites. If you fix a bug, the count should grow by however many regression tests you add; if you find no bugs, the count should be unchanged.

Run every command's full output through to its final pass/fail line. Do not summarize away a failure.

## Non-goals

Do not implement any new board feature (no new gesture, no new annotation type, no board redesign). Do not touch `Packages/AnalysisKit`, `Packages/CoachKit`, or anything outside the board's own rendering/interaction files and, if genuinely needed, the QA scripts themselves. Do not touch the live user database under any circumstances - the disposable-copy procedure exists precisely so this never happens by accident.

## When you're done

Update `handoffs/HANDOFF.md`'s "Next up" and "Current state" sections in the same style as the existing 2026-08-21/2026-08-22 entries.
Write a dated devlog under `devlogs/` in the same style, including exactly what you could and couldn't verify, with evidence (screenshot paths, AX-tree excerpts) for each of the four items.
Commit on this branch (`board-qa-verification`) and push it to `origin` - do not merge to `main` yourself, a separate integration step will handle that.
Report back plainly: whether compositing/screenshots worked in your environment, the verification result for each of the four items with evidence, any bug found and fixed (with the fix's diff described) or found and not fixed (with your diagnosis), and validation command results.
