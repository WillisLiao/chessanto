// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "AnalysisKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AnalysisKit", targets: ["AnalysisKit"])
    ],
    dependencies: [
        .package(path: "../ChessCore"),
        .package(path: "../EngineKit"),
        .package(path: "../Persistence")
    ],
    targets: [
        .target(
            name: "AnalysisKit",
            dependencies: ["ChessCore", "EngineKit", "Persistence"],
            resources: [.copy("Resources/eco.json"), .copy("Resources/eco-index.json")]
        ),
        // Precomputes Resources/eco-index.json from Resources/eco.json
        // (`swift run eco-indexer`), invoked by scripts/fetch-eco.sh.
        // Replaying the raw ~3.8k-line dataset through ChessGame at app
        // launch measured several seconds; the precomputed index makes
        // OpeningBook.loadFromBundle() a plain dictionary decode instead.
        .executableTarget(name: "eco-indexer", dependencies: ["AnalysisKit"]),
        .testTarget(
            name: "AnalysisKitTests",
            dependencies: ["AnalysisKit"],
            resources: [.copy("Resources/real-fixture-game-report-input.json"), .copy("Resources/real-fixture-game-golden-report.txt")]
        )
    ]
)
