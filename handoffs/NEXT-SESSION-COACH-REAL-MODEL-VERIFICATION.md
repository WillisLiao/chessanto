# Session: Coach real-model verification pass

## Read first

Read `handoffs/HANDOFF.md` (living state) and `PLAN.md` (product scope and
decisions) in full before doing anything else.
Do not re-litigate anything under "Product decisions (already made)" in
PLAN.md.

Search `handoffs/HANDOFF.md` for "no real-model run was possible" and
"Ollama was unavailable" - nearly every Coach-related session so far
(P4.8 purpose clarification, its audit repair, the concreteness gate) was
verified only against the test mock, never against a real running Ollama
instance. This session exists to close that gap for real.

You have unlimited usage for this session. Do not ration effort or stop
early to save budget.

## Isolation

Run this once, from the main worktree, before writing any code:

```
git worktree add -b qa/coach-real-model-verification ../chessanto-coach-real-model main
```

Do all your work inside `../chessanto-coach-real-model`.
Never edit files in the main `/Users/willis/Documents/chessanto` checkout.

This project uses XcodeGen: `Chessanto.xcodeproj` is generated from
`project.yml`, not hand-edited.
Any time you add or remove a Swift file under `App/`, `Mobile/`, or
`Packages/*`, run `xcodegen generate` in your worktree before building, or
the new file is invisible to the build and test run.

## Scope

First, get Ollama actually running: check whether it's installed
(`ollama --version` or `brew install ollama`), running
(`curl http://127.0.0.1:11434`), and has at least one model pulled that
meets the model floor introduced recently (`CoachModelCatalog.meetsModelFloor`
requires 8B+ - pull a real model such as `qwen3:8b` if none is available).
If Ollama genuinely cannot run in this environment, say so explicitly and
concretely in your devlog (what you tried, what failed) rather than
falling back to the mock and reporting it as if it were a real run.

With a real model running, exercise the full Verified Coach stack for
real, across a real batch of real games (reuse an existing large imported
library if one of the QA sessions' worktrees has built one, or fetch
several players' archives yourself):

- **Moment narration**: for a real sample of key moments across many real
  games (aim for at least 50), generate the Coach's narration and record
  whether `CoachVerifier` passes it cleanly, triggers regeneration, or
  falls back to canned text. A very high fallback rate would mean the
  concreteness gate or verifier is too strict for a real 8B model to
  satisfy in practice - that's a real finding worth investigating, not
  just a number to report.
- **Chat**: hold real multi-turn conversations against real positions,
  including at least: a plain question, a proposed-move question ("what
  about Nf3?"), a question that should trigger the evaluate tool, and a
  deliberately vague or off-topic message, to see how the
  default-closed `requiresEvaluateCall` policy and clarifier whitelist
  actually behave against a real model's real phrasing (not just the
  crafted strings in existing unit tests).
- **Model floor UI**: confirm the below-8B warning in `CoachSetupView`
  and the Coach-disable gate in `ChatView.isCoachEnabled` actually behave
  correctly against a real small model (pull something under 8B, such as
  `qwen3:4b`, to confirm the floor logic engages against a real model tag
  string, not just a hardcoded test value).

For every real defect found (a false claim that slips through
`CoachVerifier`, a legitimate response wrongly rejected by the
concreteness gate, a tool-call loop that misbehaves, a floor check that
doesn't match real Ollama model tag naming): root-cause and fix it in
`Packages/CoachKit`, and add it as a proper regression test - if it's a
real model's real output, capture the exact text as a fixture so the bug
can't silently reintroduce.

## Non-goals

- Don't touch the analysis/theme-detection pipeline in `AnalysisKit`
  unless a Coach-layer bug traces back into a fact being wrong at the
  source - if so, fix it there too, but that should be rare, not the
  bulk of this session's work.
- Don't touch Play vs Engine, Chess960, search/filter, accessibility, or
  visual QA (separate sessions own those).

## Verification bar

Nothing here is done until you have actually run it and can quote the
real output, including real model output where relevant - not
paraphrases of what the model said.

```
swift test --package-path Packages/CoachKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
```

The build must end `** BUILD SUCCEEDED **`.
The test run must end `** TEST SUCCEEDED **`, and you must quote the
"Test run with N tests in M suites" line in your devlog.

Your devlog must include real transcripts (moment narrations and chat
turns) from the real model run, not summaries, plus fallback/regeneration
rates across your sample and every defect found with its fix.

## When done

Write `devlogs/<date>-coach-real-model-verification.md` with the full
real-model verification described above and the exact verification
output.
Add a new `## Current state - Coach real-model verification` section at
the TOP of `handoffs/HANDOFF.md` (do not delete existing history there).
Commit everything on your branch (`qa/coach-real-model-verification`).
Do not merge to main. Do not push. Do not touch files outside the scope
above.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
