// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Engrave",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EngraveInterposer", targets: ["EngraveInterposer"]),
        .library(name: "EngraveGovernance", targets: ["EngraveGovernance"]),
        .executable(name: "engrave", targets: ["EngraveCLI"]),
    ],
    targets: [
        .target(
            name: "EngraveInterposer",
            path: "Sources/EngraveInterposer",
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .target(
            name: "EngraveGovernance",
            dependencies: ["EngraveInterposer"],
            path: "Sources/EngraveGovernance"
        ),
        .executableTarget(
            name: "EngraveCLI",
            dependencies: ["EngraveInterposer", "EngraveGovernance"],
            path: "Sources/EngraveCLI"
        ),
    ]
)
