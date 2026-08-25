# 2026-08-25 - Release packaging and distribution hardening audit

This audit executed the release packaging pipeline against `main` per `handoffs/NEXT-SESSION-RELEASE-PACKAGING-AUDIT.md`.

## Summary

- **Release build correctness**: `xcodegen generate` and `xcodebuild -project Chessanto.xcodeproj -scheme Chessanto -destination 'platform=macOS' -configuration Release build` succeeded with `** BUILD SUCCEEDED **`.
- **Packaging pipeline**: `scripts/release-build.sh` runs cleanly end-to-end, producing an unsigned, self-contained Release bundle at `/Users/willis/Library/Developer/Xcode/DerivedData/Chessanto-dvybgihmaxaffpbutfmycvjeqlkn/Build/Products/Release/Chessanto.app`.
- **Bundle contents & size**:
  - Total `.app` bundle size: 145 MB
  - Stockfish 17 NNUE networks bundled: `nn-1111cefa1111.nnue` (71 MB) and `nn-37f18f62d772.nnue` (3.4 MB)
  - ECO opening dataset bundled in `AnalysisKit_AnalysisKit.bundle`: `eco.json` (508 KB, 3,803 entries) and `eco-index.json` (555 KB, 3,801 unique positions)
  - Audio assets: `move.wav` (11 KB), `capture.wav` (17 KB)
  - Compiled asset catalog: `Assets.car` (8.2 MB)
  - Application icon: `AppIcon.icns` (140 KB)
- **Code signing & entitlements**:
  - `com.apple.security.app-sandbox`: true
  - `com.apple.security.network.client`: true (supports Chess.com API fetching and local Ollama inference at `http://127.0.0.1:11434`)
  - `com.apple.security.files.user-selected.read-only`: true (supports `.fileImporter` for PGN import)
  - `NSAppTransportSecurity.NSAllowsLocalNetworking`: true in `Info.plist`
- **Fresh-machine first-run simulation**:
  - Launched the packaged Release binary under macOS App Sandbox targeting a fresh disposable database in container tmp.
  - AX UI probe confirmed the first-run experience: window initializes at 1200x732, displays Sidebar with navigation (`All Games`, `Favorites`, `Player Brief`, `Play vs Engine`, `Recently Deleted`, `Search`, `Filter`), empty state actions (`Play vs Engine`, `Import PGN...`, `Fetch from chess.com...`), and presents the 4-step Onboarding modal sheet (`Your games, turned into a study record`: Welcome -> Account -> Teaching level -> Local Coach).
- **Database safety**:
  - Live database at `~/Library/Containers/com.chessanto.app/Data/Library/Application Support/Chessanto/chessanto.sqlite` was checked before and after all actions.
  - SHA-256 remained byte-identical: `3ab332c1722e43c21138b521d00703f50fbdc4b9201906b86853d9a25f661c5f`.
- **Verification bar**:
  - Release build: `** BUILD SUCCEEDED **`
  - App test run: `Test run with 261 tests in 43 suites passed after 6.664 seconds.` (`** TEST SUCCEEDED **`)
