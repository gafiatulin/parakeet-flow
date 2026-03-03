// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ParakeetFlow",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "ParakeetFlow",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")],
            path: "Sources/ParakeetFlow",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
