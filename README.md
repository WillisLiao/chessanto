# Chessanto

Chessanto is a native macOS app for reviewing your own chess games.
Import games from chess.com or a PGN file, analyze them with a real chess
engine running entirely on your Mac, and read a coached report that
explains your key moments - no cloud services, no accounts, no telemetry.

- **Import**: chess.com public API fetch, or drag-and-drop / file-picker
  PGN import.
- **Analyze**: Stockfish 17 runs in-process (no subprocess, no network) to
  produce per-move evaluations, move classifications, and accuracy.
- **Explore**: a chess.com-style analysis board - live eval bar, free
  variation play, continuous engine analysis of the displayed position.
- **Coach**: a rule-based report is always available; an optional local LLM
  (via [Ollama](https://ollama.com)) can narrate on top of it, with every
  sentence programmatically verified against the actual analysis before it
  is ever shown - the coach cannot state a move, line, or evaluation that
  isn't real.
- **Progress**: an accuracy trend and most-frequent-mistake-theme dashboard
  across your analyzed games.

## Building from source

Prerequisites: a recent Xcode (the project targets macOS 14+), and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The `.xcodeproj` is generated, not committed.

```sh
git clone https://github.com/WillisLiao/chessanto.git
cd chessanto
scripts/fetch-nnue.sh      # downloads Stockfish's NNUE evaluation networks
xcodegen generate
open Chessanto.xcodeproj
```

Build and run the `Chessanto` scheme. `swift test --package-path
Packages/<Name>` runs each local package's unit tests independently;
`xcodebuild test` (or Xcode's Test action) runs the full app test suite.

A few resources are fetched by script rather than committed as raw
downloads, each with a `scripts/fetch-*.sh` counterpart that regenerates
it:

- `scripts/fetch-nnue.sh` - Stockfish's NNUE networks (gitignored, ~78 MB;
  fetched fresh, hash-verified against the filename).
- `scripts/fetch-eco.sh` - the opening book (`Packages/AnalysisKit/Sources/AnalysisKit/Resources/eco.json`
  and its precomputed index, both committed).
- `scripts/fetch-pieces.sh` - the cburnett piece artwork
  (`App/Resources/Pieces.xcassets`, committed).

## Dependencies and licenses

Chessanto is licensed **GPLv3** (see `LICENSE`), which is required by one of
its dependencies (Stockfish) and is compatible with all the others.

| Dependency | License | Used for |
|---|---|---|
| [chesskit-swift](https://github.com/chesskit-app/chesskit-swift) | MIT | Chess rules, PGN/FEN parsing |
| [chesskit-engine](https://github.com/chesskit-app/chesskit-engine) | MIT (wrapper) | In-process Stockfish 17 bridge |
| [Stockfish](https://stockfishchess.org) 17 (vendored by chesskit-engine) | GPLv3 | The chess engine itself |
| [GRDB](https://github.com/groue/GRDB.swift) | MIT | Local SQLite persistence |
| [lichess-org/chess-openings](https://github.com/lichess-org/chess-openings) | CC0-1.0 | The bundled opening book |
| [cburnett piece set](https://github.com/lichess-org/lila/tree/master/public/piece/cburnett) (Colin M.L. Burnett, via lichess-org/lila) | GPLv2+ | Board piece artwork |

Everything else (SwiftUI, Swift Charts, GRDB's SQLite backend, Foundation)
ships with Xcode/macOS under Apple's standard terms.

## Release builds, signing, and notarization

`scripts/release-build.sh` produces an **unsigned** Release build:

```sh
scripts/release-build.sh
```

It regenerates the Xcode project, builds the `Chessanto` scheme in the
Release configuration, and prints the path to the resulting `.app`. An
unsigned build launches and runs fine locally (Gatekeeper only objects to
*distributing* an unsigned app to other Macs) - this is deliberate, so a
plain checkout always produces a runnable build without requiring anyone's
Developer ID.

To distribute a build to other people, sign and notarize it with your own
Apple Developer ID after `scripts/release-build.sh` finishes:

```sh
APP="path/to/Chessanto.app"   # printed by scripts/release-build.sh
IDENTITY="Developer ID Application: Your Name (TEAMID)"

# 1. Sign the app (deep, hardened runtime, your entitlements).
codesign --force --deep --options runtime \
  --entitlements App/Resources/Chessanto.entitlements \
  --sign "$IDENTITY" "$APP"

# 2. Zip it for submission and notarize with notarytool (requires an
#    app-specific password or API key set up via `xcrun notarytool
#    store-credentials` beforehand).
ditto -c -k --keepParent "$APP" "Chessanto.zip"
xcrun notarytool submit "Chessanto.zip" --keychain-profile "<your-profile>" --wait

# 3. Staple the notarization ticket so the app works offline/Gatekeeper-checked.
xcrun stapler staple "$APP"
```

None of this runs automatically - signing identities are yours, not the
build script's.

## Future directions

Explicitly out of scope for v1 (see `PLAN.md`): mistake-derived puzzles,
spaced repetition, repertoire training, play-vs-engine, Lichess import,
iCloud sync, Chess960.
