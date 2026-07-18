# Next session - V1 hardening phase 3

This document is a scoping starting point, not a fully verified execution plan the way `handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md` was.
Phase 2 closed the engine-correctness and grading-correctness gaps (F1 through F7) with live-reproduced diagnosis and a full six-step implementation.
Full detail is in the `V1 hardening phase 2` section of `handoffs/HANDOFF.md` and the `V1 hardening phase 2: bounded engine search and typed grading` section of `devlogs/2026-07-19.md`.

Before starting implementation, a planning session (or the start of this session) should do what the phase-2 plan's own predecessor did: read every file this phase touches in full, verify claims against the live app rather than trusting this document, and fix the design decisions before writing code.
Do not treat the candidates below as pre-verified facts.

## Starting point

The last commit that changed product code should be the phase-2 commit (check `git log` for the commit titled around "V1 hardening phase 2" or similar - this document was written before that commit existed, so it cannot name the exact hash).
Confirm `main` is clean and synchronized with `origin/main` before starting, the same way the phase-2 plan did.

This checkout has no physical `AGENTS.md`.
Do not create one to satisfy any instruction that references it, unless this session is the one executing Follow-up A below.

## Candidate scope for this phase

The obvious candidate, carried forward from phase 2's own recommendation: the full practice render-state machine, together with non-disclosing incorrect feedback and a distinct Reveal state.
Phase 2's Step 6 deliberately touched only the recovery path (a `promptError` field for `EngineSearchError`), not the full state machine `handoffs/NEXT-SESSION-V1-HARDENING.md` originally sketched.

Candidate items, all still open per phase 1 and phase 2's own "remain open" checklists:

- The full `PracticeSessionViewModel` render-state machine.
- Non-disclosing incorrect feedback (the current `.incorrect` explanation may reveal too much) and a distinct Reveal state separate from `.feedback`.
- Duplicate-submit rejection.
- Recording review decisions for Reveal and Skip.
- Dashboard and practice presentation ownership, without nested sheets.
- The 900-point replay and practice layout (the right pane clips at narrow widths, logged since the phase-1 devlog).
- Contrast, target size, keyboard, focus, announcement, and reduced-motion coverage.
- Promotion moves in practice (`PracticeSessionViewModel.swift` submits a four-character UCI string with no promotion suffix).
- README and version alignment.

A planning session should pick a bounded slice of this list, verify it against the live app the way phase 2's planning session did, and write a self-contained execution plan the way `NEXT-SESSION-V1-HARDENING-PHASE-2.md` was written - do not treat all of the above as one slice.

## Carried-forward follow-up A - add a project-level `CLAUDE.md`

Deliberately excluded from phase 2, and now also excluded from being auto-started in phase 3, because changing repository-wide instruction files during an implementation slice adds risk for no benefit.
This repository still has no project-level `CLAUDE.md` and no `AGENTS.md`.
Every durable rule still reaches the agent only through the session prompt.

The phase-3 (or a later) plan should specify capturing at least the following in a project `CLAUDE.md`:

- The forced-light warm-neutral and brass visual identity, and the rule that the board, pieces, app icon, and Chessanto identity are not to be redesigned.
- The rule that green stays confined to the board arrow and the reserved move-classification colors, and never enters application chrome.
- The native database-safety procedure, including the sandbox path, the backup step, the disposable-copy step, and the two required opt-in environment variables (`CHESSANTO_ENABLE_QA_DATABASE_OVERRIDE`, `CHESSANTO_DATABASE_PATH`).
- The standard verification command set: the per-package suites, the app suite, `engine-smoke`, `coach-grounding`, and `scripts/release-build.sh`.
- The rule that `xcodegen generate` must run after adding or removing files, because `Chessanto.xcodeproj` is generated and gitignored.
- The documentation rules already in force: one full sentence per physical line in Markdown, never the em dash character, no modification of `CHANGELOG.md` or generated files, and no agent co-author on commits.
- The native AX-scripting tooling and its known sharp edges, since this session found two worth recording: `scripts/axclick.swift ... --last` is needed when a match string could collide with sidebar badge text (e.g. "Analyze" is a substring of "Analyzed"), and `scripts/axclickat.swift`'s raw screen-coordinate clicks were unreliable for at least one toolbar button regardless of window width, where `axclick.swift`'s AX-action-based press worked.

This is a documentation change only.
It must not alter behavior, and it must not silently become a place to invent new rules the project has not actually agreed.

## Carried-forward follow-up B - author a root `CONTEXT.md`

Also deliberately excluded from phase 2 and phase 3's auto-start, for the same reason.
The project's domain vocabulary still exists only as prose spread across `handoffs/HANDOFF.md` and the devlogs.
Representative terms now also include, beyond phase 2's own additions: bounded search, search generation vs. delivery generation, white-perspective score, terminal position short circuit, and the FIFO chokepoint pattern (`coachEvaluateTail`).

Four installed skills read a root `CONTEXT.md` when one exists: `tdd`, `diagnosing-bugs`, `improve-codebase-architecture`, and `ask-matt`.
Each guards the read with an explicit existence check, so its absence is a missed opportunity rather than a defect.

Use the `domain-modeling` skill to author it, following its `CONTEXT-FORMAT.md`.
Do not hand-roll a format.
Do not use `setup-matt-pocock-skills` for this, since that skill only records where domain documents live and never writes their content.

Schedule this once V1 hardening is closed rather than in the middle of it, since the payoff is compounding rather than immediate.

## A known, unrelated bug found during phase 2's E2E acceptance

Not phase-2 scope, not fixed, recorded here so it is not lost.
The `Hikaru vs Casablanca` chess.com import in the QA database snapshot (gameId 2 as of the phase-2 session) fails to load with `Couldn't parse this game's PGN: ChessKit.PGNParser.Error error 2`.
This matches the parser edge case already logged in the 2026-07-17 M4 devlog section (`invalidMove("Rb5")` on a different game) - a pre-existing `chesskit-swift` parser gap, not a chess.com-specific or phase-2 regression.
Whoever picks up practice-state or accessibility work should not be surprised by it; it is not this phase's job to fix a third-party PGN parser edge case unless the user asks for it explicitly.

## Recommended skills

Follow phase 2's own pattern.
`implement` to drive whichever slice gets planned.
`diagnosing-bugs` before touching anything claimed to be broken - phase 2 found the prior planning session's own diagnosis (F2) was real but incomplete, and only live re-reproduction caught that.
`tdd` for every step.
`codebase-design` for any new seam (the render-state machine is the obvious candidate).
`mattpocock-skills:code-review` before the final commit of whatever slice gets executed, with that slice's own plan document as the spec axis.
