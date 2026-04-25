// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MLXLauncher",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "./Engrave"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.21.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", from: "3.31.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "0.1.12"),
    ],
    targets: [
        .executableTarget(
            name: "MLXLauncher",
            dependencies: [
                .product(name: "EngraveInterposer", package: "Engrave"),
                .product(name: "EngraveGovernance", package: "Engrave"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Transformers", package: "swift-transformers"),
            ],
            path: "Sources",
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("Network"),
            ]
        ),
        .executableTarget(
            name: "MLXLauncherTestSuite",
            path: "Tests/MLXLauncherTestSuite"
        )
    ]
)
