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
        .testTarget(name: "ChessComKitTests", dependencies: ["ChessComKit"])
    ]
)
