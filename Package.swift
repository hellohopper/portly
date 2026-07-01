// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Porty",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Porty",
            path: "Sources/Porty"
        ),
        .testTarget(
            name: "PortyTests",
            dependencies: ["Porty"],
            path: "Tests/PortyTests"
        )
    ]
)
