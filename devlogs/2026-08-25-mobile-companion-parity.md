# 2026-08-25 - iPhone companion feature parity and hardening pass

This session executed the companion parity audit and hardening plan specified in `handoffs/NEXT-SESSION-MOBILE-COMPANION-PARITY.md` in branch `feature/mobile-companion-parity` at worktree `/Users/willis/Documents/chessanto-mobile-parity`.

## Parity audit and gap analysis

1. **Tactical facts and detectors propagation**:
   - Audited the pipeline from Mac analysis (`ReportBuilder.swift`, `PortableReportAssembler.swift`) through encrypted mailbox serialization (`PortableAnalysisReport`, `PortableKeyMoment`, `AuditedCoachNarration`) to the phone companion (`OfflineReportReader.swift`, `OfflineReportCache.swift`).
   - Verified that all tactical facts (absolute pin, fork, skewer, discovered attack, back-rank weakness, trapped piece, ignored threat, eval swing, move quality) are serialized into structured sentences in `PortableKeyMoment.summary` and `AuditedCoachNarration.text`.
   - In `OfflineReportReader.swift`, enhanced key moment cards to display move numbers (`14... Nf3`, `15. Bxh7+`), move classification badges (`MobileClassificationChip`), and evaluation pill indicators.
   - Enhanced the scoresheet move list in `OfflineReportReader.swift` to look up move classifications from portable key moments and render standard compact annotation marks (`★`, `!!`, `?!`, `?`, `??`) next to SAN move text.

2. **Dynamic dark mode support**:
   - The Mac app introduced a warm-neutral palette with dynamic dark mode. The mobile companion's `MobileDesignSystem.swift` previously had static light hex values and `ChessantoMobileApp.swift` had `.preferredColorScheme(.light)`.
   - Updated `MobileColors` in `MobileDesignSystem.swift` using dynamic `UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light }` mapped to the Mac app palette:
     - `paper`: `#FAF9F6` / `#1C1A17`
     - `paperRaised`: `#FFFFFF` / `#2D2A26`
     - `parchment`: `#F3F0E9` / `#252220`
     - `graphite`: `#26231F` / `#E8E2D6`
     - `graphiteSoft`: `#625E57` / `#A09A8E`
     - `brass`: `#A6791F` / `#C9A04A`
     - `brassWash`: `#F2E8D2` / `#3A3220`
     - `hairline`: `#DDD8CE` / `#3D3A35`
     - `success`: `#2D6E49` / `#4EAA74`
     - `danger`: `#B42318` / `#E55A4F`
   - Added `MobileClassificationStyle` providing dynamic semantic colors and compact marks for all 10 move classifications (`best`, `excellent`, `good`, `book`, `inaccuracy`, `mistake`, `blunder`, `brilliant`, `great`, `forced`).
   - Removed `.preferredColorScheme(.light)` from `ChessantoMobileApp.swift` so the iOS companion automatically adapts to system light and dark appearance seamlessly.

3. **Pairing and invitation robustness**:
   - Hardened `PairingInvitationQRCodec.decode` in `CompanionSecurity` to trim whitespace and newline characters from input strings prior to URL component parsing.
   - Hardened `MobileAppModel.submitPairingCode` to trim whitespace and newlines from manual code entries.
   - Added unit test `pairingInvitationCodecToleratesWhitespace` in `PairingSecurityTests.swift`.

4. **[%clk] time-pressure takeaways & Coach model floor**:
   - Verified that clock takeaways generated on the Mac side are packaged directly into `PortableAnalysisReport.coach` (`AuditedCoachNarration.text` and `bulletPoints`), which the mobile companion renders in `coachSection` and `keyMoments`.
   - Verified that Mac analysis backend model floor guards prevent running small sub-8B models for coach generation, delivering consistent audited reports to the phone.

5. **Test suite expansion**:
   - Added `Mobile/Tests/ChessantoMobileTests/MobileCompanionParityTests.swift` covering:
     - All 10 move classification styles, labels, colors, and compact marks.
     - Dynamic light/dark trait collection color resolution for all design tokens.
     - Round-trip offline report caching with complex reports containing multiple fact types (pins, forks, ignored threats, eval swings, and time pressure takeaways).

6. **Visual pass on iOS Simulator**:
   - Booted iOS simulator (`iPhone 15`, `id=1CDE4CAF-A0D6-4215-B08F-CE654CAA16B3`), built and launched `ChessantoMobile.app`.
   - Captured and verified visual renderings in both dark mode (`#1C1A17` warm dark background, brass tab tints, crisp typography) and light mode (`#FAF9F6` warm paper background).

## Exact verification output

1. **CompanionKit package tests**:
   ```
   swift test --package-path Packages/CompanionKit
   ```
   Output:
   ```
   Test run with 33 tests in 11 suites passed after 0.063 seconds.
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
   Test run with 211 tests in 37 suites passed after 3.039 seconds.
   ** TEST SUCCEEDED **
   ```

5. **iOS Mobile target build**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'generic/platform=iOS Simulator' build
   ```
   Output:
   ```
   ** BUILD SUCCEEDED **
   ```

6. **iOS Mobile target tests on simulator**:
   ```
   xcodebuild -project Chessanto.xcodeproj -scheme ChessantoMobile -destination 'platform=iOS Simulator,id=1CDE4CAF-A0D6-4215-B08F-CE654CAA16B3' test
   ```
   Output:
   ```
   ✔ Test run with 7 tests in 4 suites passed after 0.191 seconds.
   ** TEST SUCCEEDED **
   ```
