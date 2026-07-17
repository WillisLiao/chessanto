// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CoachKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CoachKit", targets: ["CoachKit"])
    ],
    dependencies: [
        .package(path: "../ChessCore"),
        .package(path: "../EngineKit"),
        .package(path: "../AnalysisKit")
    ],
    targets: [
        .target(name: "CoachKit", dependencies: ["ChessCore", "EngineKit", "AnalysisKit"]),
        // Live grounding harness (`swift run coach-grounding`): real Ollama
        // + real in-process Stockfish + the committed fixture. Kept as an
        // executable rather than a test for the same reason as EngineKit's
        // engine-smoke - chesskit-engine's response delivery needs a free
        // main run loop, which XCTest doesn't guarantee.
        .executableTarget(name: "coach-grounding", dependencies: ["CoachKit", "EngineKit", "ChessCore", "AnalysisKit"]),
        .testTarget(
            name: "CoachKitTests",
            dependencies: ["CoachKit", "ChessCore", "AnalysisKit"],
            resources: [
                .copy("Resources/real-fixture-game-report-input.json"),
                .copy("Resources/real-fixture-game-golden-report.txt"),
                .copy("Resources/real-fixture-first-moment-golden-payload.json"),
                .copy("Resources/real-fixture-first-moment-golden-chat-payload.json"),
            ]
        )
    ]
)
