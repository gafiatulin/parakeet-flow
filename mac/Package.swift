// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParakeetFlow",
    platforms: [.macOS(.v15)],
    dependencies: [
        // Pinned for reproducible builds.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-huggingface.git", exact: "1.0.0"),
        .package(url: "https://github.com/mattt/AnySpeechRecognizer.git", exact: "0.1.0"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "ParakeetFlow",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
                .product(name: "HuggingFace", package: "swift-huggingface"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "AnySpeechRecognizer", package: "AnySpeechRecognizer"),
            ],
            path: "Sources/ParakeetFlow",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
