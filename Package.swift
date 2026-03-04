// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParakeetFlow",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ParakeetFlow",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
            ],
            path: "Sources/ParakeetFlow",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
