# Next session: M6 planning/prep - local LLM coach

**This is a planning/prep session, not an execution session.** M1-M5 are
done and pushed to `main` at https://github.com/WillisLiao/chessanto. Your
job is the same role M2's and M5's prep sessions played (see the
2026-07-17 devlog's "M2 prep" section and the "Write M5 execution plan"
commit): turn this file from a bootstrap into a fully self-contained,
pre-verified execution plan - the way `NEXT-SESSION-M5.md` read before the
M5 execution session started - for a **later session to execute**. Do not
write CoachKit implementation code in this session; do the verification
work and write the plan.

M6 is the most architecturally involved milestone yet (an LLM in the
loop, a tool-calling loop, output verification), which is exactly why it
needs this dedicated prep pass: **spend this session verifying Ollama's
real local API against a live `ollama serve` instance** (model list,
pull-with-progress, chat/generate streaming, tool calling if you want the
engine-tool loop to use it) rather than guessing at request/response JSON
shapes - curl the real endpoints and paste real responses into the plan
you write. Do the same for every other "verify" item below. When you're
done, this file should read like `NEXT-SESSION-M5.md` does now: a
"Verified facts" section with things actually checked against real
source/APIs this session, "Fixed design decisions" the execution session
must not re-litigate, and a step-by-step build order with a verification
gate per step.

Read in this order before writing any code:
1. `handoffs/HANDOFF.md` - current state section only (M5's summary is at
   the top).
2. `PLAN.md`'s "Verified Coach" section in full, and the M6 milestone
   bullet. This is the actual design; nothing here should contradict it.
3. The 2026-07-17 devlog's M5 section, for exact known-gap detail.

## What M5 already built that M6 consumes

- **`AnalysisKit`'s Facts are the typed vocabulary M6's prompts should be
  built from**: `EvalSwingFact`, `BetterMoveFact`, `PunishmentFact`,
  `MissedMateFact`, `AllowedMateFact`, `OpeningFact` (all in
  `Packages/AnalysisKit/Sources/AnalysisKit/Facts.swift`), assembled per
  key moment into a `KeyMoment` by `ReportBuilder`, and gated by
  `FactAuditor` before ever reaching `ReportText`. PLAN.md's "Layer 1 -
  structured input" for the LLM should be a JSON serialization of these
  same Facts (plus the position/PV data they cite), not a fresh
  re-derivation - one source of truth.
- **`FactAuditor` is explicitly "the seed of M6's `CoachVerifier`"** (see
  its doc comment). It currently re-verifies each Fact by re-running the
  same `ThemeDetector` function and comparing. `CoachVerifier`'s job is
  different in kind, not just degree: it must parse arbitrary LLM prose
  for embedded SAN/UCI tokens and move sequences (regex + ChessCore
  parsing per PLAN.md's Layer 2), then verify each against the engine
  payload or a fresh Stockfish call - `FactAuditor`'s fixed-shape
  comparisons don't directly generalize to that, but its verify-and-drop
  posture and its "never trust, always re-derive" discipline should carry
  over exactly.
- **`ChessGame.replayLine(fromUCI:startingFEN:)`** (ChessCore) is the
  primitive both `FactAuditor` and (almost certainly) `CoachVerifier` need
  to re-verify a cited line actually plays and matches the claimed SAN/
  check/mate state - reuse it, don't reimplement.
- **The M2 engine-integration facts still apply** (see
  `NEXT-SESSION-M2.md`/the M2 devlog for the full detail): white-perspective
  DB values, single shared `AnalysisEngine` actor with a position-generation
  counter, Debug-build Stockfish is 5-10x slower than Release, NNUE nets
  required (`scripts/fetch-nnue.sh`). PLAN.md's Layer 3 ("engine as a
  tool") means the LLM triggers on-demand Stockfish searches mid-response -
  this will need to share (or carefully coordinate with) `EngineService`'s
  existing single-engine-instance design, since M2 built that around
  "exactly one live/batch analysis session at a time," not concurrent
  ad-hoc tool-call searches.

## Known gaps carried in from M5 (fix opportunistically, not blocking)

1. **Report tab key-moment buttons aren't accessibility-labeled** (role
   `AXButton`, clickable, click-to-jump confirmed working via AX-element
   reference - but `name`/`title`/`description`/`value` are all empty
   despite an explicit `.accessibilityLabel`). See the M5 devlog section
   for everything tried. If M6's coach UI needs similar per-key-moment
   controls (e.g. "ask the coach about this moment"), solving this now
   would avoid inheriting the same gap.
2. **The "Starting engine..." toolbar state exists and is structurally
   correct but wasn't caught live in automation** (Release-build engine
   starts faster than System Events can query the window post-launch).
   Low priority to re-verify; the code is a straightforward `!isStarted`
   guard.
3. Eval-label formatting can render `-0.0` for small negative centipawn
   values (cosmetic only, pre-existing, shared by `EvalLabel`).
4. All of M3's still-open gaps (promote/collapse variation controls, no
   promotion picker, mainline-equality quirk) and M4's (one real
   chess.com game fails to parse on `invalidMove("Rb5")`,
   `ChessComFetchView` doesn't paginate) remain untouched.

## Verified facts to re-confirm are still true (don't re-derive, just spot-check)

- `Packages/CoachKit/Package.swift` already declares dependencies on
  `ChessCore`, `EngineKit`, and `AnalysisKit` - the M1 architecture
  anticipated this. `CoachKit` itself is still just a placeholder
  (`CoachKit.swift`) with no real code.
- PLAN.md's model-picker RAM table (`qwen3:4b`/`8b`/`32b` etc.) was
  written at plan time, not verified against Ollama's current model
  library - confirm these tags still resolve via `ollama pull` /
  the Ollama model registry before building the picker UI around them.
- `userProfile` (Persistence) already has a `chessComUsername` column
  (M4) - it likely needs `ratingBand`/`coachModel`/`coachEnabled` columns
  added for M6's settings (mentioned as a forward-looking note in the M4
  devlog section, never implemented). Check the current `Schema.swift`
  before assuming these exist.

## Suggested shape (not a rigid plan - validate against the live Ollama API first)

1. **Ollama detection + health check**: `GET http://127.0.0.1:11434/api/tags`
   (or whatever the real current endpoint is - verify) to detect
   installation/running state; install guidance UI when absent, per
   PLAN.md.
2. **Model picker onboarding**: RAM/chip detection via `sysctl`, the
   PLAN.md table, pull-with-progress (Ollama's pull API streams progress
   events - verify the exact shape live).
3. **Structured payload assembly**: map a `KeyMoment` (+ its `ReportInput`
   context) into the JSON payload PLAN.md's Layer 1 describes.
4. **`CoachVerifier`**: SAN/UCI extraction regex, ChessCore-based legality
   + line verification, eval-claim tolerance checking, regenerate-once-
   then-fallback-to-rule-based-text policy.
5. **Engine-tool loop**: bounded `evaluate(fen, moves)` tool calls (cap
   ~6 per response per PLAN.md), coordinated with `EngineService`.
6. **UI**: LLM narration replacing/augmenting `GameReportView`'s key
   moment text when the coach is enabled; settings for teaching level/
   model choice/coach on-off (off = M5's existing rule-based text -
   the M5 report should keep working standalone forever, this is an
   additive layer).
7. **Grounding test harness**: PLAN.md calls for an automated harness
   that runs `CoachVerifier` over batches of generated output and fails
   CI on any leak - this is explicitly part of the M6 accept criterion,
   not a nice-to-have.

## Working style notes (carried forward; they keep paying off)

- Verify third-party APIs (Ollama's, in this case) against a real live
  instance before coding against them - every M-session so far caught a
  wrong assumption this way.
- Real E2E through the built app via `osascript`/System Events
  AX-element references only (raw pixel clicks and screenshots are
  blocked in this sandbox). Confirm click-to-jump / any new controls the
  same way M2-M5 did.
- After adding/removing files under `App/`, rerun `xcodegen generate`.
- Debug on stderr, never stdout (the engine hijacks stdout); Release
  builds for anything timing-sensitive.
- Commit and push milestone work together with updated handoffs and a
  dated devlog entry.
