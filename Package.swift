// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portly",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Portly", targets: ["Portly"]),
        // Not "portly": the app binary is "Portly" and macOS filesystems are
        // case-insensitive, so the two products would collide in .build/.
        // Homebrew's cask aliases this to plain `portly` on install.
        .executable(name: "portly-cli", targets: ["PortlyCLI"])
    ],
    targets: [
        // Foundation-only scanning/enrichment logic shared by the app and the CLI.
        .target(
            name: "PortlyCore",
            path: "Sources/PortlyCore"
        ),
        .executableTarget(
            name: "Portly",
            dependencies: ["PortlyCore"],
            path: "Sources/Portly"
        ),
        .executableTarget(
            name: "PortlyCLI",
            dependencies: ["PortlyCore"],
            path: "Sources/PortlyCLI"
        ),
        .testTarget(
            name: "PortlyTests",
            dependencies: ["Portly", "PortlyCore", "PortlyCLI"],
            path: "Tests/PortlyTests"
        )
    ]
)
