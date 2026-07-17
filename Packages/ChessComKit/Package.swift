// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ChessComKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChessComKit", targets: ["ChessComKit"])
    ],
    dependencies: [],
    targets: [
        .target(name: "ChessComKit"),
        .testTarget(
            name: "ChessComKitTests",
            dependencies: ["ChessComKit"],
            resources: [.copy("Resources/sample-archive.json")]
        ),
        // Live API smoke run (`swift run chesscom-smoke <username>`), mirroring
        // EngineKit's engine-smoke: hits the real chess.com API so shape
        // surprises get caught here, not through SwiftUI.
        .executableTarget(name: "chesscom-smoke", dependencies: ["ChessComKit"])
    ]
)
