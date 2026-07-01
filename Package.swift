// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Portly",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Portly",
            path: "Sources/Portly"
        ),
        .testTarget(
            name: "PortlyTests",
            dependencies: ["Portly"],
            path: "Tests/PortlyTests"
        )
    ]
)
