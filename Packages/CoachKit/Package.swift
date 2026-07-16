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
        .testTarget(name: "CoachKitTests", dependencies: ["CoachKit"])
    ]
)
