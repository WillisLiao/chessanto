# Chessanto iPhone companion handoff

## Start here

This handoff is for a fresh Codex session implementing Chessanto's approved iPhone-first companion.

Read this file completely before changing code.

Then read `handoffs/HANDOFF.md`, `handoffs/CODEX-HANDOFF-PHASE-3.md`, and `handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-3.md`.

Inspect the current source after reading those documents because the source is authoritative.

Work from the current `main` branch.

The desktop redesign, phase 2 playable analysis, comic Coach, automatic better-line playback, and selectable `Nf3` versus `Knight f3` notation are implemented, tested, committed, and pushed.

Do not re-plan or reimplement those desktop features.

The iPhone companion itself is the work for this session.

## Fixed product decision

Build the iPhone companion first.

Do not reopen iPhone versus Android as a product question.

Use an Apple-first transport based on the user's CloudKit private database and `CKSyncEngine`.

Android and web are out of scope for this version.

The companion is an asynchronous native app, not remote desktop software and not a compressed copy of the Mac workspace.

The Mac remains authoritative for Stockfish, Ollama, PGNs, analysis rows, and the primary SQLite database.

The iPhone can browse an encrypted catalog, request analysis on the Mac, monitor durable job progress, cancel a request, receive completed analysis, and study downloaded reports offline.

The Mac must be awake, online, running Chessanto, and have Companion enabled.

Do not promise remote wake or immediate real-time delivery.

## Product contract

The iPhone has three primary tabs.

`Reports` contains downloaded reports, active requests, and offline study.

`Games` contains the encrypted game catalog published by the Mac and the `Analyze on Mac` action.

`Mac` contains pairing, last-contact state, approved-device management, storage controls, and privacy explanations.

The Mac app gains `Send to iPhone` for completed analysis and `Analyze and send` for an unanalyzed game.

The phone must remain useful without connectivity after a report has downloaded.

An offline report must include game metadata, PGN, position sequence, evaluation series, ranked lines, classifications, opening, key moments, takeaways, and any verified Coach narration generated on the Mac.

The rule-based report is always available.

If Coach is enabled and reachable, include verified Coach prose.

If Coach is disabled, unavailable, or fails verification, include and label the safe rule-based fallback.

Open-ended remote Coach chat is not part of version 1.

The phone may submit only bounded commands for opaque game identifiers already published by the paired Mac.

Do not allow arbitrary prompts, PGN uploads, file paths, shell input, or generic remote commands.

The mobile report reader must support the same user-facing notation choice as the Mac.

Keep canonical SAN in the portable report and apply `Nf3` or `Knight f3` only at the presentation boundary.

## Visual direction

Match the desktop product's editorial analysis-desk language.

Use warm white surfaces, graphite text, restrained brass accents, hairline rules, strong alignment, and native controls.

Do not return to rounded card grids, decorative gradients, icon tiles, excessive pills, or generic SaaS dashboard composition.

The report reader should feel like a portable annotated scoresheet.

Give the board and current critical moment priority.

Use a continuous reading surface with ruled sections for accuracy, opening, key moments, engine alternatives, and takeaways.

Use brass only for active state, the current move, evidence rules, and the primary action.

Use a maximum of three bottom tabs.

Respect Dynamic Type, VoiceOver reading order, Reduce Motion, contrast, and a minimum 44-point touch target.

Show explicit pressed, loading, empty, offline, failed, and stale states.

Never rely on hover.

Use honest status language such as `Queued`, `Waiting for Mac`, `Analyzing on Willis's Mac`, `Packaging report`, and `Saved for offline reading`.

Do not show an indefinite `Connecting` state.

## Pairing and security

Use one private CloudKit custom record zone for the paired user's companion mailbox.

Initialize `CKSyncEngine` early in both app processes and persist its state across launches.

Use explicit fetches on launch, foreground, pull to refresh, and lifecycle changes.

Treat push notifications as advisory.

Use CloudKit encrypted fields as a second protection layer.

Encrypt sensitive payloads in the app before upload.

Store private device keys and content keys in Keychain.

Use CryptoKit signing and key-agreement keys per device.

The Mac creates a short-lived QR pairing invitation.

The phone scans the invitation and publishes its public device keys plus proof of the one-time invitation secret.

The Mac displays a matching verification phrase and requires explicit approval.

The Mac then wraps the endpoint content key to the approved phone using the devices' key-agreement keys.

Pairing invitations expire after five minutes and can be used only once.

Device revocation blocks future commands and triggers content-key rotation.

Revocation cannot erase reports already downloaded to a phone, and the UI must state that clearly.

CloudKit can still observe record type, size, timing, and account-level metadata.

State that limitation accurately in privacy copy.

## Cloud record model

Use immutable request records and Mac-owned status records to avoid multi-writer conflicts.

`MacEndpoint` contains the opaque endpoint identifier, protocol version, capabilities, public keys, and last-contact timestamp.

`PairingCandidate` contains the phone's public keys, invitation proof, display name, and creation timestamp.

`DeviceApproval` contains the approved phone identifier, permissions, and wrapped content key.

`GameCatalog` contains a versioned encrypted catalog snapshot owned by the Mac.

`AnalysisRequest` contains an immutable signed and encrypted request owned by the phone.

`AnalysisCancellation` contains an immutable signed cancellation request owned by the phone.

`AnalysisStatus` contains the Mac-owned monotonic job snapshot.

`ReportSnapshot` contains encrypted portable report metadata and an encrypted `CKAsset` when the payload is too large for an inline field.

Keep queryable metadata minimal and non-sensitive.

Bind the record identifier, protocol version, sender, recipient, and message identifier into authenticated data.

## Job state and reliability

Every phone request has a stable UUID that serves as the idempotency key.

Use the monotonic states `submitted`, `queued`, `accepted`, `waitingForEngine`, `analyzing`, `packaging`, `transferring`, and `completed`.

Use `failed`, `cancelled`, `expired`, and `rejected` as terminal alternatives.

The Mac must durably record a verified request before engine work begins.

The Mac processes one remote analysis job at a time because the existing engine has one owner.

Duplicate delivery of the same UUID returns the current stored job state and never starts a second analysis.

The same UUID with a different authenticated payload is rejected as tampering.

Requests expire after 24 hours unless already accepted.

A user retry creates a new request UUID that references the failed request.

Cancellation is best effort.

If engine work has already completed, the Mac may finish packaging and mark the cancellation too late.

The UI must distinguish `Mac has not received this yet` from `Mac accepted this`.

The existing per-ply analysis cache should continue to provide crash and interruption recovery.

## Required analysis-provenance correction

The current `EngineService.analyze` checks only whether a ply already has a rank-1 row.

The persisted analysis does not record which analysis-quality preset produced that row.

A remote Deep request could therefore silently reuse a Fast or Standard result.

Fix analysis provenance before exposing remote quality selection.

Add a new forward-only migration after the current schema version.

Never edit an existing migration.

Record at least the quality preset and analysis timestamp for each saved ply.

Record an engine identifier or version if the bundled engine exposes one reliably.

Treat legacy rows with unknown quality as insufficient for an explicit higher-quality remote request.

Define and test the reuse rule centrally.

A stored result may satisfy a request only when its recorded quality is equal to or stronger than the requested quality.

Preserve partial resume at the ply level.

Do not delete all prior analysis whenever a remote request arrives.

## Module boundaries

Create a shared package with deep, narrow interfaces rather than putting CloudKit calls directly in views.

Use `Packages/CompanionKit/CompanionDomain` for versioned identifiers, catalogs, commands, job states, portable reports, reducers, canonical encoding, and protocol compatibility.

Use `Packages/CompanionKit/CompanionSecurity` for pairing, signatures, encryption, key wrapping, expiry, replay protection, and Keychain adapters.

Use `Packages/CompanionKit/CompanionCloudKit` for record encoding, `CKSyncEngine`, the custom zone, subscriptions, state persistence, inbox, outbox, retries, and CloudKit error mapping.

Keep CloudKit behind a transport protocol so domain and application-service tests use a deterministic in-memory mailbox.

Add Mac integration under `App/Sources/Chessanto/Companion`.

Add the iPhone app under a clearly separate `Mobile` source and resource tree.

Add `ChessantoMobile` and `ChessantoMobileTests` targets to `project.yml`.

Use iOS 17 as the initial deployment target unless dependency verification proves that a higher minimum is required.

Inspect portable package manifests before changing platform declarations.

Do not make `EngineKit` or the Mac persistence layer dependencies of the iPhone target.

Use a dedicated, versioned, `Codable` `PortableAnalysisReport` rather than leaking database records into the wire format.

Keep the iPhone cache separate from the Mac's primary Chessanto database.

Keep companion receipts, device state, and sync state in a separate Mac companion store.

Map opaque companion game UUIDs to local game IDs without exposing SQLite `Int64` identifiers.

Do not make the remote path construct or drive `GameReplayViewModel`.

Extract a UI-independent game-analysis application service used by both the existing replay UI and the remote coordinator.

Keep `EngineService` as the single engine owner.

Serialize local and remote batch requests through one coordinator.

Publish progress from the application service rather than reading SwiftUI view state.

## Implementation sequence

Use a red-green-refactor vertical slice for each step.

First add golden encoding tests for the versioned catalog, request, job snapshot, and portable report.

Then add reducer tests for monotonic transitions, terminal-state immutability, duplicate delivery, expiry, cancellation, and tamper rejection.

Then add crypto tests for signature verification, wrong-recipient rejection, ciphertext tampering, expired invitations, single-use invitations, key wrapping, key rotation, and replay rejection.

Then add analysis-quality provenance tests before changing production analysis reuse.

Then extract the UI-independent analysis service with deterministic mock engine and store tests.

Then implement the in-memory mailbox and a full Mac-to-phone contract test without CloudKit.

Then implement CloudKit record mapping and sync-state persistence against a mocked CloudKit boundary.

Then implement the iPhone local cache, view models, and production UI.

Then add the Mac pairing, device-management, `Send to iPhone`, and `Analyze and send` UI.

Finally run a physical-device CloudKit development acceptance test if signing and a CloudKit container are available.

Do not invent a development team identifier or CloudKit container.

Discover existing signing configuration first.

If no Apple Developer team or CloudKit container is configured, finish the deterministic local transport and all testable product code, document the exact external provisioning blocker, and stop before guessing account settings.

## Required acceptance scenarios

Pair an iPhone with explicit Mac approval.

Reject an expired or reused invitation.

Publish the Mac game catalog and read it on the phone.

Queue analysis while the Mac is unavailable.

Start queued analysis after the Mac becomes available.

Show progress without duplicating engine work after repeated delivery.

Close and reopen the phone app while analysis continues.

Cancel a queued request and handle a cancellation that arrives after completion.

Complete analysis, download the report, and open it in airplane mode.

Navigate key moments and the board offline.

Send an already analyzed game from the Mac without rerunning the engine.

Request Deep analysis when only weaker or legacy cached analysis exists.

Reject a signed command from a revoked device and rotate keys after revocation.

Handle iCloud sign-out, account switching, quota errors, zone deletion, encrypted-key reset, and temporary network failures with honest recovery UI.

Verify both move-notation modes, Dynamic Type, VoiceOver, Reduce Motion, touch targets, and offline messaging.

Verify that the live Mac database checksum is unchanged after native QA.

## Verification and database safety

The current desktop baseline passes 98 app tests across 23 suites, all package tests, engine smoke, Coach grounding, and the universal Release build.

Re-run the full matrix after implementation.

The build and test commands are documented in `handoffs/CODEX-HANDOFF-PHASE-3.md`.

Never run native QA against the live database at `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite`.

Copy it to a QA path, record the live checksum before launch, point the app at the QA copy through the existing QA override, and verify the live checksum again at the end.

Use a fresh companion CloudKit development zone or deterministic fake account for destructive sync tests.

Do not run destructive fixtures against a production CloudKit container.

## Documentation and delivery

Do not leave locally testable companion work as a plan.

Implement through the deepest acceptance boundary available without external signing or CloudKit credentials.

Create a locked in-repo execution record after verifying the current source.

Update `handoffs/HANDOFF.md` with the completed outcome.

Append actual work and verification evidence to the current dated file in `devlogs`.

Use one full sentence per physical line in Markdown.

Never use an em dash character.

Never edit generated changelogs or shipped migrations.

Regenerate the Xcode project after target or source changes.

Commit without an agent co-author.

Push only after implementation, tests, native QA, documentation, and live-database verification are complete.

## Prompt for the next session

Read `/Users/willis/Documents/chessanto/handoffs/NEXT-SESSION-IPHONE-COMPANION.md` first.

Then read `/Users/willis/Documents/chessanto/handoffs/HANDOFF.md`, `/Users/willis/Documents/chessanto/handoffs/CODEX-HANDOFF-PHASE-3.md`, and `/Users/willis/Documents/chessanto/handoffs/NEXT-SESSION-UIUX-CLARITY-PHASE-3.md`.

Implement the approved iPhone-first Chessanto companion completely from the handoff.

Inspect current source before making changes, follow the test-first sequence, and never modify or test against the live Chessanto database.
