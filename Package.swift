// swift-tools-version: 5.10
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
        )
    ]
)
