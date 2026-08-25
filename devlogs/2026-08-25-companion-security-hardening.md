# 2026-08-25 - Companion pairing and sync security hardening pass

This session executed the companion security audit and hardening plan specified in `handoffs/NEXT-SESSION-COMPANION-SECURITY-HARDENING.md` on branch `feature/mobile-companion-parity` at worktree `/Users/willis/Documents/chessanto-mobile-parity`.

## Trust model architecture

The Chessanto companion trust boundary provides end-to-end cryptographic authentication, confidentiality, and integrity between the Mac app and the iPhone companion over private CloudKit transport:

1. **Device Identity and Keys**:
   - Each endpoint generates two Curve25519 keypairs: an Ed25519 signing keypair (`Curve25519.Signing.PrivateKey`) and an X25519 key agreement keypair (`Curve25519.KeyAgreement.PrivateKey`).
   - Private key material is stored securely in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and `kSecAttrSynchronizable: false`, preventing iCloud Keychain sync and cross-device leakage.

2. **Pairing Flow and Key Agreement**:
   - Mac creates a time-bounded `PairingInvitation` containing its endpoint ID, Ed25519 and X25519 public keys, a cryptographically secure 32-byte one-time secret (`SecRandomCopyBytes`), and an Ed25519 signature over canonical JSON.
   - Phone scans the QR code (`chessanto://pair?v=1&invitation=<base64url>`), verifies the signature and key validity, and generates a `PairingCandidate` containing an HMAC-SHA256 proof over its identity and public keys using the invitation's one-time secret.
   - Mac verifies the candidate proof using constant-time `HMAC<SHA256>.isValidAuthenticationCode`, derives a 256-bit wrapping key via X25519 Diffie-Hellman + HKDF-SHA256 (salted with the one-time secret), encrypts the session's 256-bit symmetric `contentKey` using AES-GCM, and produces a 4-word Short Authentication String (SAS) verification phrase.
   - Phone unwraps the content key using its X25519 private key and the Mac's X25519 public key.

3. **Envelope Encryption and Transport Integrity**:
   - Outbound companion messages are serialized to canonical JSON and sealed in an `AuthenticatedEnvelope`.
   - Payload is encrypted with AES-GCM using the shared 256-bit `contentKey`, authenticating the envelope header (record ID, protocol version, message ID, sender, recipient) as Additional Authenticated Data (AAD).
   - Entire envelope (header + ciphertext) is signed by the sender's Ed25519 private key.
   - Recipient verifies recipient address, sender Ed25519 signature against approved device public keys, AES-GCM tag authentication, and deduplicates message IDs through `SecureEnvelopeInbox` to prevent replays.
   - `SecureCompanionCloudMailbox` verifies that outer unencrypted CloudKit record metadata matches the authenticated inner envelope header.

## Defects found and root-cause fixes

1. **`PairingInvitationQRCodec` URL and payload robustness**:
   - **Finding**: Custom URL scheme and host comparison were case-sensitive (`components.scheme == "chessanto"`), which could reject valid QR codes scanned by third-party camera apps that uppercase URLs (`CHESSANTO://PAIR`). Payload decoding errors allowed generic `DecodingError` to escape instead of failing with typed `PairingInvitationQRCodecError.invalidPayload`.
   - **Fix**: Lowercased scheme and host before comparison and caught decoding errors to cleanly throw `PairingInvitationQRCodecError.invalidPayload`.

2. **`PairingInvitationVerification` incomplete key and interval checks**:
   - **Finding**: Phone verified the Mac's Ed25519 signing key but did not validate the X25519 agreement public key, did not verify 32-byte length bounds on `oneTimeSecret`, did not check 64-byte signature length bounds, and did not check for inverted validity intervals (`createdAt > expiresAt`).
   - **Fix**: Added validation for `macPublicKeys.agreement` via `Curve25519.KeyAgreement.PublicKey(rawRepresentation:)`, checked `oneTimeSecret.count == 32`, checked `signature.count == 64`, and asserted `invitation.expiresAt > invitation.createdAt`.

3. **`PairingAuthority.approve` candidate validation and timing safety**:
   - **Finding**: `approve` validated the candidate's X25519 agreement key but did not validate the Ed25519 signing key or empty device ID before saving the approved device. Proof comparison used standard `Data` equality rather than constant-time HMAC validation.
   - **Fix**: Added `Curve25519.Signing.PublicKey(rawRepresentation: candidate.publicKeys.signing)` validation, checked non-empty `candidate.deviceID.rawValue`, and switched to constant-time `HMAC<SHA256>.isValidAuthenticationCode`.

4. **`ContentKeyWrapping.unwrap` symmetric key length check**:
   - **Finding**: `unwrap` opened the AES-GCM sealed box and wrapped the result in `SymmetricKey(data:)` without asserting that the decrypted key was exactly 32 bytes (256 bits).
   - **Fix**: Added an explicit `guard openedKeyData.count == 32 else { throw PairingError.malformedWrappedKey }`.

5. **`AuthenticatedEnvelope` bounds and header validation**:
   - **Finding**: `seal` and `open` did not validate non-empty message ID and record ID strings, and `open` did not assert minimum payload bounds (28 bytes: 12-byte nonce + 16-byte tag) or 64-byte signature length before invoking CryptoKit.
   - **Fix**: Added explicit header field validation, signature length check (64 bytes), and payload size check (>= 28 bytes) in `seal` and `open`.

6. **`KeychainSecretStore` update accessibility preservation**:
   - **Finding**: `SecItemUpdate` updated only `kSecValueData`, which could allow updated secrets to drift if originally inserted with different attributes.
   - **Fix**: Added `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` to update attributes.

7. **`AnalysisRequestLedger.admit` interval validation**:
   - **Finding**: `admit` checked `request.expiresAt > now` but did not reject requests with inverted validity intervals (`request.expiresAt <= request.createdAt`) or empty request IDs.
   - **Fix**: Added `guard !request.id.rawValue.isEmpty, request.expiresAt > now, request.expiresAt > request.createdAt else { return .rejected(.expired) }`.

## Adversarial test coverage expansion

- **Pairing and QR Code (`PairingSecurityTests.swift`)**:
  - Malformed and adversarial URLs: empty strings, arbitrary non-URLs, HTTP URLs, incorrect hosts, missing `v` parameter, unsupported version `v=2`, missing invitation query, corrupt base64, valid base64 with non-JSON payload.
  - Case-insensitive scheme and host QR decoding (`CHESSANTO://PAIR`).
  - Corrupted public keys (truncated signing key, truncated agreement key).
  - Truncated one-time secrets (< 32 bytes).
  - Inverted invitation timestamps (`createdAt > expiresAt`).
  - Truncated signatures (< 64 bytes).
  - Adversarial candidates: unknown invitation ID, forged HMAC proof, corrupted signing key, corrupted agreement key, empty device ID.
  - Key wrapping: bad Mac agreement public key, bit-flipped ciphertext, truncated ciphertext (< 28 bytes), incorrect one-time secret.
  - Replay protection on invitations (cannot be approved twice).

- **Envelope Encryption (`AuthenticatedEnvelopeTests.swift`)**:
  - Valid envelope seal and open round-trip.
  - Tampered header fields (modified recordID, modified sender).
  - Truncated and empty ciphertexts.
  - Truncated and forged Ed25519 signatures.
  - Content key mismatch (valid signature, failed AES-GCM tag).
  - Sender key mismatch.
  - Empty header fields rejection on seal and open.
  - Replay protection in `SecureEnvelopeInbox`.

- **Keychain Storage (`KeychainSecretStoreTests.swift`)**:
  - Round-trip save, load, and remove.
  - Loading nonexistent account returns nil.
  - Removing nonexistent account succeeds cleanly.
  - Updating existing account overwrites secret and preserves strict accessibility.
  - Multiple distinct accounts within the same service are completely isolated.

- **CloudKit Record Mapper (`CompanionCloudRecordMapperTests.swift`)**:
  - Small envelope routing metadata vs encrypted payload.
  - Large envelope asset spilling.
  - Missing envelope payload detection.
  - Pairing candidate and approval record mapping round-trip and missing payload detection.

- **Secure Cloud Mailbox (`SecureCompanionCloudMailboxTests.swift`)**:
  - Outer CloudKit recordName vs inner envelope header recordID tampering detection.
  - Outer queryable sender and recipient tampering detection.
  - Unapproved or revoked sender rejection.
  - Mismatched CloudKit record type rejection.

- **Phone Pairing Store (`PhonePairingStoreTests.swift`)**:
  - First-launch identity generation and persistence.
  - Pairing lifecycle: invitation storage, approval completion, content key storage, and clean reset.

## Exact verification output

1. **CompanionKit package tests**:
   ```
   swift test --package-path Packages/CompanionKit
   ```
   Output:
   ```
   Test run with 50 tests in 11 suites passed after 0.101 seconds.
   ```

2. **XcodeGen project generation**:
   ```
   xcodegen generate
   ```
   Output:
   ```
   Created project at /Users/willis/Documents/chessanto-mobile-parity/Chessanto.xcodeproj
   ```

3. **macOS target build**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' build
   ```
   Output:
   ```
   ** BUILD SUCCEEDED **
   ```

4. **macOS target tests**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' test
   ```
   Output:
   ```
   Test run with 222 tests in 39 suites passed after 6.911 seconds.
   ** TEST SUCCEEDED **
   ```

5. **iOS Mobile target build**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' build
   ```
   Output:
   ```
   ** BUILD SUCCEEDED **
   ```

6. **iOS Mobile target tests on simulator**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,name=iPhone 17' test
   ```
   Output:
   ```
   ✔ Test run with 11 tests in 5 suites passed after 0.232 seconds.
   ** TEST SUCCEEDED **
   ```
