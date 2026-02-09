// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwitchFix",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SwitchFixApp",
            dependencies: ["Core", "Dictionary", "UI", "Utils"],
            path: "Sources/SwitchFixApp"
        ),
        .target(
            name: "Core",
            dependencies: ["Dictionary", "Utils"],
            path: "Sources/Core"
        ),
        .target(
            name: "Dictionary",
            dependencies: [],
            path: "Sources/Dictionary",
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "UI",
            dependencies: ["Core", "Utils"],
            path: "Sources/UI"
        ),
        .target(
            name: "Utils",
            dependencies: [],
            path: "Sources/Utils"
        ),
        .testTarget(
            name: "SwitchFixTests",
            dependencies: ["Core", "Dictionary", "Utils"],
            path: "Tests/SwitchFixTests"
        ),
    ]
)
