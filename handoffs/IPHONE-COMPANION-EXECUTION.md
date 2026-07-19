# iPhone companion execution record

Date: 2026-07-19

This record closes the implementation described by `NEXT-SESSION-IPHONE-COMPANION.md`.
It also includes the user's session additions for Coach speech, emotional Coach portraits, visible progress, and explicit-only key-moment playback.

## Delivered product

Chessanto now has an iPhone-first companion target with Reports, Games, and Mac tabs.
The iPhone can establish an approved cryptographic relationship with the Mac, request local analysis while Chessanto is open on the Mac, observe progress, cancel work, receive the completed portable report, and retain downloaded reports for offline review.
The Mac remains the only analysis host.
Stockfish, Coach generation, and the Chessanto database stay on the Mac.

`Packages/CompanionKit` owns the shared protocol in three modules.
`CompanionDomain` owns versioned identifiers, canonical messages, catalogs, jobs, portable reports, cancellation, reducers, and durable idempotency.
`CompanionSecurity` owns signed pairing invitations, Curve25519 agreement and signing, explicit phrase approval, wrapped content keys, AES-GCM envelopes, replay defense, rotation, revocation, and device-only Keychain storage.
`CompanionCloudKit` owns the private custom zone, immutable record contract, encrypted record and asset mapping, `CKSyncEngine` state, durable outbox recovery, and secure mailbox validation.

The Mac and iPhone persist enough companion state to resume safely after relaunch.
The Mac writes a durable analysis-request ledger before engine work starts, so a replayed or redelivered request cannot start duplicate analysis.
The iPhone persists its catalog and in-flight jobs.
Completed reports are encrypted with a device-only Keychain key before they are written to the iPhone's offline cache.

## Analysis and persistence

Local Replay analysis and iPhone-requested analysis now pass through the same `GameAnalysisApplicationService`.
The service centralizes reuse policy, job progress, report assembly, and cancellation boundaries.
Remote status is streamed as work advances instead of being buffered until report packaging finishes.

The forward-only `v9_analysisProvenance` migration adds analysis quality, analysis time, and engine identity.
Legacy rows without provenance are not treated as reusable companion results.
Weaker or incompatible cached work is also rejected by the centralized reuse policy.
No shipped migration was edited.

## Mac and iPhone interface

The Mac sidebar exposes Pair iPhone and paired-state access to Companion Settings.
Companion Settings covers a five-minute QR invitation, manual code, matching phrase approval, rejection, approved-device management, revocation, mailbox recovery, and privacy disclosure.
The replay workspace can send a completed report to an approved iPhone.

The iPhone Games tab shows Mac-published games, quality choice, analysis requests, cancellation, and exact progress such as `3 of 10`.
The Reports tab retains downloaded reports and opens a board-first offline reader with evaluations, key moments, move score sheet, takeaways, and Coach guidance.
The Mac tab owns pairing, sync recovery, and privacy explanation.

Both apps use clear empty, unavailable, waiting, active, failed, cancelled, and completed states.
When CloudKit signing is absent, both apps show the exact external setup requirement instead of crashing or pretending to be connected.

## Voiced and emotional Coach

The Coach can speak on both macOS and iPhone through explicit Hear, Pause, Resume, and Stop controls.
Speech never starts automatically.
The voice selection prefers an installed older British voice and falls back to another English voice while retaining the slower, lower-pitched original wise-teacher delivery.
The implementation is an original sage voice and does not imitate a named performer or copyrighted character.

The Coach now has resting, thoughtful, concerned, encouraging, instructive, and delighted portraits.
Report stages, practice feedback, chat messages, and the iPhone offline reader select an emotion deterministically from the current coaching content.
The visible portrait, spoken text, and written text therefore describe the same coaching moment.

## Session corrections

The analysis interface now exposes progress directly as an `x of total` step count.

Selecting a key moment now only selects its position and stops any earlier line preview.
It does not start the recommended continuation.
Only the explicit Show better line or Replay better line control starts playback.
Focused intent tests and native Release QA both cover this correction.

An unsigned QA build exposed a Keychain permission prompt during startup.
The root cause was that Companion identity secrets were loaded before the app checked whether this build had a configured CloudKit container.
Startup now performs the provisioning check first, so an unconfigured build shows its honest setup message without touching Companion Keychain data.

## Verification

`CompanionKit` passes 32 tests across 11 suites.
The complete macOS app suite passes 107 tests across 27 suites.
The iPhone suite passes 4 tests across 3 suites, including encrypted offline report persistence, companion-only deletion, relaunch persistence for catalogs and in-flight jobs, and explicit-only better-line playback.
The other package suites pass at their final counts: `ChessCore` 21, `AnalysisKit` 63, `CoachKit` 74, `EngineKit` 1, `ChessComKit` 4, and `Persistence` 40.
The live Stockfish smoke checks and ten-run Coach grounding checks pass.
The universal arm64 and x86_64 Release build succeeds.

Native Mac QA launched the Release app only with both database-override variables against `/Users/willis/Library/Containers/com.chessanto.app/Data/tmp/iphone-companion-20260719-211052/chessanto.sqlite`.
The running process was verified with `lsof` to have the QA database open.
Companion Settings rendered the provisioning blocker without a Keychain prompt or CloudKit exception.
The replay screen rendered the emotion-specific Coach portrait and Hear Coach control.
Selecting the `4...Nxe4` key moment jumped to its position and then remained stable.
Pressing Replay better line subsequently advanced the board.

Native iPhone QA ran on the iPhone 17 Pro simulator.
Reports, Games, and Mac navigation rendered correctly.
The Mac tab presented Secure Mac pairing, the explicit CloudKit signing blocker, retry, and privacy disclosure.

The live database was backed up before QA at `/Users/willis/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite.before-iphone-companion-20260719-211052`.
Its MD5 was `26f0882ad0e3ffdfc7a065a5791f8b5f` before QA and the same after every QA process was closed.
The live Chessanto database therefore remained byte-identical.

## External provisioning boundary

This checkout does not contain an Apple Developer team or a private iCloud container identifier.
Those values cannot be invented in source control.
Physical Mac-iPhone CloudKit acceptance requires the owner to add the same private iCloud container to both targets, add the corresponding entitlements, and provide `ChessantoCloudKitContainerIdentifier` in each built product.
All pairing, cryptographic, mailbox, progress, cancellation, report-transfer, relaunch, and offline-cache behavior that can be exercised without those credentials is implemented and covered locally.
