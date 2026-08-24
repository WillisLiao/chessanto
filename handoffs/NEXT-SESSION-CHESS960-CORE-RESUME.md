# Session: Chess960 - core rules and import (RESUME)

A prior instance was working on this and hit a usage limit mid-task. Its
worktree already exists with substantial uncommitted work. Do not start
over and do not discard that work without reading it first.

## Read first

Read `handoffs/NEXT-SESSION-CHESS960-CORE.md` in full - it has the
complete scope, non-goals, and verification bar for this task, including
the explanation of what Chess960 is. Everything in it still applies. This
file only covers how to resume correctly.

## Resuming (do this before anything else)

```
cd /Users/willis/Documents/chessanto-chess960-core
git status
git diff --stat
```

Read every changed and new file. The prior instance left:
- A new `Packages/ChessCore/Sources/ChessCore/Chess960.swift` (~600
  lines) - this is the bulk of the work, likely the starting-position
  generator, FEN handling, and castling-legality adaptation described in
  the task file.
- A new `Packages/ChessCore/Tests/ChessCoreTests/Chess960Tests.swift`
  (~290 lines).
- Modifications to `Packages/AnalysisKit/Sources/AnalysisKit/OpeningBook.swift`
  and its tests (likely the "opening book must not fire for 960 games"
  requirement).
- Modifications to `Packages/ChessCore/Sources/ChessCore/ChessGame.swift`
  and `PGNCompatibility.swift`.

No devlog exists yet, and nothing has been committed - this work has not
been verified end to end. Read `Chess960.swift` and its tests closely:
check the two core invariants (bishops on opposite colors, king strictly
between the rooks) are actually enforced and tested for all 960 positions
as the task file requires, not just a handful of sampled ones. Check
whether FEN castling-rights notation for non-standard rook files was
actually addressed (Shredder-FEN or an equivalent) - this is the part
most likely to be incomplete or wrong if the prior instance ran out of
budget partway through.

Evaluate the work on its merits: continue what's sound, fix or simplify
what's wrong or over-built. Once you understand what's there, commit it
as a checkpoint before changing anything further:

```
git add -A
git commit -m "Checkpoint: carry forward Chess960 core work in progress"
```

Then continue the task through to actual completion per
`handoffs/NEXT-SESSION-CHESS960-CORE.md`: verify against at least one real
Chess960 game PGN exported from Lichess or chess.com, and meet the file's
full verification bar (the exact `swift test` and `xcodebuild` commands,
with real quoted output, not a summary).

## When done

Follow the "When done" section of `handoffs/NEXT-SESSION-CHESS960-CORE.md`
exactly (devlog, `HANDOFF.md` section, commit on `feature/chess960-core`,
no merge, no push). Also write the "Handoff to the integration session"
note the original file asks for - the app-integration session is waiting
on it.
