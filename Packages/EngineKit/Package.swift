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
        .testTarget(name: "EngineKitTests", dependencies: ["EngineKit"])
    ]
)
