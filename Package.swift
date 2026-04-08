// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AiUsageApp",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "AiUsageApp",
            targets: ["AiUsageApp"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "AiUsageApp",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AiUsageAppTests",
            dependencies: ["AiUsageApp"]
        ),
    ]
)
