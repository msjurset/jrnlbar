// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JrnlBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "JrnlBar",
            path: "Sources/JrnlBar"
        )
    ]
)
