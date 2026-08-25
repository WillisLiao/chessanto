# Session: Companion pairing and sync security hardening

## Why this session is safe to run in parallel

An overnight `opencode` run is working through `handoffs/OVERNIGHT-INTEGRATION-MASTER.md`
right now, merging branches into `main` and polishing the Mac app. Its
scope is `App/`, `Packages/ChessCore`, `Packages/AnalysisKit`,
`Packages/CoachKit`, `Packages/Persistence`, `Packages/EngineKit`, and
`Packages/ChessComKit`. This session's scope is the companion's security
layer only: `Packages/CompanionKit/Sources/CompanionSecurity/` and
`Packages/CompanionKit/Sources/CompanionCloudKit/`. Nothing in the
overnight run's plan touches those.

## Continue in the existing worktree - do not create a new one

This continues directly from the two companion sessions already done.

```
cd /Users/willis/Documents/chessanto-mobile-parity
git status
git log --oneline -5
```

You should see branch `feature/mobile-companion-parity`, clean, with
commits for the parity pass and the accessibility pass on top of it.
Read `devlogs/2026-08-25-mobile-companion-parity.md` and
`devlogs/2026-08-25-mobile-accessibility.md` (or whatever the
accessibility session actually named its devlog - check `devlogs/` for
today's date if that exact name isn't there) to see what's already been
touched, particularly the `PairingInvitationQRCodec` and
`MobileAppModel.submitPairingCode` hardening from the parity pass - this
session goes much further on the same surface.

Sync with `main` first:

```
git fetch origin
git merge origin/main
```

## Read first

Read `handoffs/HANDOFF.md` and `PLAN.md` in full if you haven't already
this session. Do not re-litigate anything under PLAN.md's "Product
decisions (already made)" section.

## Scope

This is the companion's trust boundary - it's how a phone and a Mac
prove to each other they should be talking, and how analysis data
travels between them. Treat it with the seriousness a real security
review deserves, not a quick pass.

- **Read every file in `CompanionSecurity` and `CompanionCloudKit` end to
  end first** - `PairingSecurity.swift`, `PairingInvitationQRCodec.swift`,
  `AuthenticatedEnvelope.swift`, `KeychainSecretStore.swift`, and
  whatever else is there - before writing anything, so you understand the
  actual trust model (what proves identity, what's encrypted versus just
  signed, what a replay or tampering attempt would look like) rather than
  guessing at it from function names.
- **Adversarial input testing on the pairing flow**: malformed QR
  payloads, truncated/corrupted invitation strings, replayed old
  invitations, invitations for a different device, whitespace/encoding
  edge cases beyond what the parity pass already covered, and anything
  that could trick `submitPairingCode` into accepting something it
  shouldn't.
  For each: does it fail closed (reject cleanly) or could it fail open
  (accept something it shouldn't, or crash into an inconsistent state)?
  Fix anything that fails open or crashes; a clean, deliberate rejection
  is the correct behavior and doesn't need "fixing," just a regression
  test proving it stays that way.
- **`AuthenticatedEnvelope` tampering tests**: flip bits in an encrypted
  payload, truncate it, replay an old envelope, swap the sender/recipient
  context if that's a concept here - confirm authentication actually
  catches every one of these rather than silently decrypting garbage or
  accepting a stale message.
- **Keychain storage**: confirm secrets are actually stored with
  appropriate accessibility/protection class (not, e.g., accessible
  without device unlock when they shouldn't be), and that deletion
  actually removes them rather than leaving orphaned entries.
- **CloudKit sync robustness**: if there's conflict handling for
  concurrent writes from Mac and phone, or a schema-version assumption
  that could break on a partial/interrupted sync, test what happens on
  a malformed or partial record. Physical multi-device CloudKit testing
  isn't possible in this environment - say so explicitly where it
  applies rather than claiming untested behavior works, and focus on
  what you can verify locally (encoding/decoding round trips, conflict-
  resolution logic in isolation).

For every real defect found, fix it at the root and add a regression
test that would catch it coming back. This is exactly the kind of trust
boundary the project's own standards call out as never appropriate to
simplify away for expediency.

## Non-goals

- Don't touch `App/`, `Packages/ChessCore`, `Packages/AnalysisKit`,
  `Packages/CoachKit`, `Packages/Persistence`, `Packages/EngineKit`, or
  `Packages/ChessComKit`.
- Don't touch `CompanionDomain` or the Mobile UI layer unless a security
  fix genuinely requires a small change there (e.g. how a rejected
  pairing attempt is surfaced to the user) - keep it as narrow as the
  actual fix needs.
- Don't build new companion features - this is a hardening pass on what
  already exists.

## Verification bar

```
swift test --package-path Packages/CompanionKit
xcodegen generate
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' test
```

(If `iPhone 17` isn't available, run `xcrun simctl list devices available`
and use a real available device name instead - don't skip the simulator
run.)

Every build must end `** BUILD SUCCEEDED **` and every test run must end
`** TEST SUCCEEDED **`, with the real "Test run with N tests in M suites"
line quoted in your devlog - it should be higher than the 33
`CompanionKit` tests and 9 mobile tests already there, given the
adversarial cases this session adds. Pipe long xcodebuild output through
`tail` or `grep -E "error:|BUILD SUCCEEDED|TEST SUCCEEDED|Test run with"`
rather than reading it raw.

## Bookkeeping

Write `devlogs/<date>-companion-security-hardening.md` describing the
trust model as you found it, every adversarial case tested, every real
defect found and fixed, and the exact verification output. Extend the
`## Current state - Mobile companion parity` section (or add a new
dated section directly above it) at the top of `handoffs/HANDOFF.md` in
this worktree - don't delete the existing history. Commit everything on
the same branch (`feature/mobile-companion-parity`). Do not merge to
main yourself and do not push.

## Style

Never use an em dash anywhere in code, comments, commits, or docs. Use a
plain dash instead.
No boilerplate or speculative abstractions beyond what the task needs.
