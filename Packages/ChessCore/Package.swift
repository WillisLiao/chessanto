// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ChessCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ChessCore", targets: ["ChessCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/chesskit-app/chesskit-swift.git", from: "0.17.0")
    ],
    targets: [
        .target(
            name: "ChessCore",
            dependencies: [
                .product(name: "ChessKit", package: "chesskit-swift")
            ]
        ),
        .testTarget(name: "ChessCoreTests", dependencies: ["ChessCore"])
    ]
)
