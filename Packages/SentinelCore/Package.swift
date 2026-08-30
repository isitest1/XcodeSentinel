// swift-tools-version: 6.0
import PackageDescription

// SentinelCore holds every piece of logic that does NOT depend on macOS.
// It builds and tests on Linux inside the dev container. It must never import
// AppKit, SwiftUI or ApplicationServices — see CLAUDE.md sections 4.2 and 15.
let package = Package(
    name: "SentinelCore",
    // Apple-platform floor. The app itself targets macOS 15 (CLAUDE.md 1.6);
    // the logic package only needs APIs available from macOS 13 (e.g.
    // JSONEncoder.OutputFormatting.withoutEscapingSlashes). No effect on the
    // Linux build.
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SentinelCore", targets: ["SentinelCore"])
    ],
    targets: [
        .target(
            name: "SentinelCore",
            resources: [
                .process("Resources/Patterns.json")
            ]
        ),
        .testTarget(
            name: "SentinelCoreTests",
            dependencies: ["SentinelCore"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
