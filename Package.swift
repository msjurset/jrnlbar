// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "JrnlBar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // VimEngine lives in its own repo so other apps can depend on
        // the same versioned package without copying files.
        // Pinned exact while v1.0.1 (which added @MainActor — source-
        // breaking for non-actor-isolated callers like the test target)
        // is being sorted out. Bump to `from: "1.0.0"` after we either
        // adapt the test code or re-tag the breaking change as 2.0.0.
        .package(url: "https://github.com/msjurset/swift-vim-engine.git", exact: "1.0.0")
    ],
    targets: [
        .target(
            name: "JrnlBarLib",
            dependencies: [
                .product(name: "VimEngine", package: "swift-vim-engine")
            ],
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
            dependencies: [
                "JrnlBarLib",
                .product(name: "VimEngine", package: "swift-vim-engine")
            ],
            path: "Tests/JrnlBarTests"
        )
    ]
)
