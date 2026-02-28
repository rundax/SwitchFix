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
            exclude: [
                "Resources/uk_full.txt"
            ],
            resources: [
                .copy("Resources/en_US.txt"),
                .copy("Resources/ru_RU.txt"),
                .copy("Resources/uk_UA.txt"),
                .copy("Resources/overrides")
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
        .executableTarget(
            name: "TestRunner",
            dependencies: ["Core", "Dictionary", "Utils"],
            path: "Sources/TestRunner"
        ),
    ]
)
