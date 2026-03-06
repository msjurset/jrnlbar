// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JrnlBar",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "JrnlBarLib",
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
            dependencies: ["JrnlBarLib"],
            path: "Tests/JrnlBarTests"
        )
    ]
)
