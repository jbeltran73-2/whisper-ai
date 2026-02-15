// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HolaAI",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HolaAI",
            targets: ["HolaAI"]
        )
    ],
    dependencies: [
        // Future dependencies will be added here
    ],
    targets: [
        .executableTarget(
            name: "HolaAI",
            dependencies: [],
            path: "Sources/HolaAI",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "HolaAITests",
            dependencies: ["HolaAI"],
            path: "Tests/HolaAITests"
        )
    ]
)
