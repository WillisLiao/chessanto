# Next Claude session - Opus planning for Sonnet medium

## Purpose

Use Claude Opus for one planning-only session.
The output must be a concrete, self-contained execution plan for one subsequent Claude Sonnet medium session.
Do not implement product code during the Opus planning session.

The next implementation session should continue V1 hardening, not start a new feature area.
Prefer one coherent risk-reduction slice that Sonnet medium can complete, verify, document, commit, and push without carrying hidden assumptions into another session.

## Prompt to give Claude Opus

```text
You are planning the next Chessanto implementation session.
Use Claude Opus for this task.
This is planning and live verification only.
Do not change product code.

Start from the latest main branch and verify that it is clean and synchronized with origin/main.
The expected tip is the commit named "Harden training card reconciliation and review UI".

Read these files completely before planning:

- The repository and workspace AGENTS.md instructions that apply to this checkout.
- handoffs/HANDOFF.md.
- The V1 hardening execution section and final review hardening section in devlogs/2026-07-18.md.
- handoffs/NEXT-SESSION-V1-HARDENING.md.
- handoffs/NEXT-SESSION-LEARNING-LOOP.md.
- The relevant source and tests for every seam you propose changing.

Treat the first V1 hardening slice as complete:

- Familiar chess-review marks replaced the old classification abbreviations.
- Training cards use the exact audited pre-move FEN.
- Learner-owned report filtering is implemented.
- Transactional reconciliation inserts, updates, deletes, preserves unchanged progress, resets changed answers, validates persisted data, and rolls back invalid candidates.
- v5_trainingIndexes is forward-only and has an existing-v4 preservation plus foreign-key integrity test.
- Report practice readiness is awaited, retryable, generation-safe, and gated by reconciled source ply.
- Dashboard historic backfill is personalized, cancellable, failure-aware, and followed by a fresh consistent queue snapshot.
- Dashboard reloads after practice and does not use its old captured lesson arrays.
- App synchronization tests and persistence upgrade tests exist and pass.
- Native QA already proved that the stale starting-position lesson is replaced by an insightful real pre-move position.

Do not plan those items again unless source inspection finds a concrete regression.

The remaining hardening work is still open:

- Bounded engine search completion, timeout, cancellation, and late-bestmove isolation.
- Typed training scores and correct cached-line grading.
- A full PracticeSessionViewModel render-state machine with non-disclosing incorrect feedback, distinct Reveal, duplicate-submit rejection, cancellation, retry, and accurate completion semantics.
- Dashboard and practice presentation ownership without nested sheets.
- The 900-point replay and practice layout.
- Contrast, target size, keyboard, focus, announcements, reduced motion, and native capture coverage.
- README and version alignment only after the full acceptance gates pass.

Plan the highest-risk coherent next slice for one Claude Sonnet medium implementation session.
Strongly consider bounded engine search plus the minimum typed grading seam it needs, because that is the highest-ranked unresolved correctness risk.
If live inspection proves a different dependency order is safer, explain the evidence and choose that order.

Before writing the plan:

1. Reproduce the current behavior through the native app or a production-aligned executable wherever practical.
2. Inspect the exact engine callback and continuation lifecycle in EngineService, AnalysisEngine, BatchCollector, and the live smoke harness.
3. Inspect current training evaluation and PracticeSessionViewModel boundaries.
4. Identify which existing tests can be extended and which new tests are required.
5. Confirm the sandbox and disposable-database procedure from the devlog.
6. Preserve all user changes and avoid unrelated cleanup.

Write the plan to handoffs/NEXT-SESSION-V1-HARDENING-PHASE-2.md.
Make it directly executable by Claude Sonnet medium with no further design interview.

The plan must contain:

- A short verified diagnosis with file and symbol references.
- Explicit in-scope and out-of-scope boundaries sized for one Sonnet medium session.
- Fixed architectural decisions and the reasons for each seam.
- A red-green-refactor sequence with small verification gates.
- Exact cancellation, timeout, stale-result, and recovery semantics.
- Exact test names and commands.
- A production-aligned E2E reproduction and acceptance scenario.
- Native data-safety instructions.
- Documentation, devlog, commit, and push requirements.
- A final checklist that prevents claiming later V1 work as complete.
- Suggested skills for the Sonnet session.

Apply the repository rule that every full sentence in a substantially edited Markdown document occupies its own physical line.
Never use the em dash character.
Do not modify CHANGELOG.md or generated files.
Do not add an agent co-author to commits.

End the Opus session by reporting:

- The path to the new phase-2 plan.
- The verified starting commit.
- The exact one-line prompt the user should give Claude Sonnet medium.
- Any blocker that requires a user decision before implementation.
```

## Suggested skills for the Opus planning session

- Use `diagnosing-bugs` to reproduce the engine lifecycle risk before settling the plan.
- Use `codebase-design` to place the bounded-search and typed-score seams.
- Use `grill-with-docs` only if a real architectural ambiguity survives source and runtime inspection.

## Suggested skills for the Sonnet medium implementation session

- Use `implement` to execute the phase-2 plan.
- Use `tdd` for every engine lifecycle and grading behavior.
- Use `diagnosing-bugs` for native reproduction before each bug fix.
- Use `codebase-design` for the engine and training module boundaries.
- Use `ui-ux-pro-max` together with the repository's frontend or interface-design skill if the chosen phase includes any UI or interaction change.
- Use `review` before the final commit.

## Sources of truth

`handoffs/HANDOFF.md` is the chronological project snapshot.
`devlogs/2026-07-18.md` contains the exact native QA and command record.
`handoffs/NEXT-SESSION-V1-HARDENING.md` is the full release-hardening backlog and acceptance contract.
This document only routes the next planning session and intentionally does not duplicate those artifacts.
