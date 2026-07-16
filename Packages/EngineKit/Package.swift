// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "EngineKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EngineKit", targets: ["EngineKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/chesskit-app/chesskit-engine.git", from: "0.7.0"),
        .package(path: "../ChessCore")
    ],
    targets: [
        .target(
            name: "EngineKit",
            dependencies: [
                .product(name: "ChessKitEngine", package: "chesskit-engine"),
                "ChessCore"
            ]
        ),
        // Live Stockfish smoke run (`swift run engine-smoke`). Kept as an
        // executable rather than a test because chesskit-engine's response
        // delivery needs a free main run loop, which XCTest doesn't
        // guarantee - the reason its own Stockfish tests are disabled
        // upstream. See Sources/engine-smoke/main.swift.
        .executableTarget(name: "engine-smoke", dependencies: ["EngineKit"]),
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit"])
    ]
)
