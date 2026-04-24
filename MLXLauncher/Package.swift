// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MLXLauncher",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Engrave"),
    ],
    targets: [
        .executableTarget(
            name: "MLXLauncher",
            dependencies: [
                .product(name: "EngraveLib", package: "Engrave"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("Network"),
            ]
        )
    ]
)
