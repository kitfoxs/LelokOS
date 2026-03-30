// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LelokOS",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "LelokOS",
            path: "LelokOS/Shared"
        )
    ]
)
