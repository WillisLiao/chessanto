// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Persistence",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Persistence", targets: ["Persistence"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(path: "../ChessCore")
    ],
    targets: [
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                "ChessCore"
            ]
        ),
        .testTarget(name: "PersistenceTests", dependencies: ["Persistence"])
    ]
)
