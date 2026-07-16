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
            resources: [.copy("Resources/eco.json")]
        ),
        .testTarget(name: "AnalysisKitTests", dependencies: ["AnalysisKit"])
    ]
)
