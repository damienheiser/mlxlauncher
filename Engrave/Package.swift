// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Engrave",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EngraveLib", targets: ["EngraveLib"]),
        .executable(name: "engrave", targets: ["EngraveCLI"]),
    ],
    targets: [
        .target(
            name: "EngraveLib",
            path: "Sources/EngraveLib",
            linkerSettings: [
                .linkedFramework("Network"),
            ]
        ),
        .executableTarget(
            name: "EngraveCLI",
            dependencies: ["EngraveLib"],
            path: "Sources/EngraveCLI"
        ),
    ]
)
