// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JrnlBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // Exported so other Swift packages / Xcode projects can depend
        // on the portable vim component directly.
        .library(name: "VimEngine", targets: ["VimEngine"])
    ],
    targets: [
        .target(
            name: "VimEngine",
            path: "Sources/VimEngine",
            exclude: ["README.md"]
        ),
        .target(
            name: "JrnlBarLib",
            dependencies: ["VimEngine"],
            path: "Sources/JrnlBar",
            exclude: ["JrnlBarApp.swift"]
        ),
        .executableTarget(
            name: "JrnlBar",
            dependencies: ["JrnlBarLib"],
            path: "Sources/JrnlBarMain"
        ),
        .executableTarget(
            name: "JrnlBarTests",
            dependencies: ["JrnlBarLib", "VimEngine"],
            path: "Tests/JrnlBarTests"
        )
    ]
)
