// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WhisperAI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "WhisperAI",
            targets: ["WhisperAI"]
        )
    ],
    dependencies: [
        // Future dependencies will be added here
    ],
    targets: [
        .executableTarget(
            name: "WhisperAI",
            dependencies: [],
            path: "Sources/WhisperAI",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "WhisperAITests",
            dependencies: ["WhisperAI"],
            path: "Tests/WhisperAITests"
        )
    ]
)
