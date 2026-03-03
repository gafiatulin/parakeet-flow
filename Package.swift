// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ParakeetFlow",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ParakeetFlow",
            path: "Sources/ParakeetFlow",
            exclude: ["Resources/Info.plist"]
        ),
    ]
)
