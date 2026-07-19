// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "CompanionKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "CompanionDomain", targets: ["CompanionDomain"]),
        .library(name: "CompanionSecurity", targets: ["CompanionSecurity"]),
        .library(name: "CompanionCloudKit", targets: ["CompanionCloudKit"]),
    ],
    targets: [
        .target(name: "CompanionDomain"),
        .target(
            name: "CompanionSecurity",
            dependencies: ["CompanionDomain"],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .target(
            name: "CompanionCloudKit",
            dependencies: ["CompanionDomain", "CompanionSecurity"],
            linkerSettings: [.linkedFramework("CloudKit")]
        ),
        .testTarget(
            name: "CompanionDomainTests",
            dependencies: ["CompanionDomain"]
        ),
        .testTarget(
            name: "CompanionSecurityTests",
            dependencies: ["CompanionSecurity", "CompanionDomain"]
        ),
        .testTarget(
            name: "CompanionCloudKitTests",
            dependencies: ["CompanionCloudKit", "CompanionSecurity", "CompanionDomain"]
        ),
    ]
)
