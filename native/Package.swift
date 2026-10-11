// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "YappingToAPiNative",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "yapping-to-a-pi-helper", targets: ["YappingToAPiHelper"]),
        .executable(name: "yapping-to-a-pi", targets: ["YappingToAPiApp"])
    ],
    targets: [
        .target(name: "YappingCore"),
        .executableTarget(name: "YappingToAPiApp", dependencies: ["YappingCore"]),
        .executableTarget(
            name: "YappingToAPiHelper",
            dependencies: ["YappingCore"],
            path: "Sources/YappingToAPiHelper"
        ),
        .testTarget(name: "YappingCoreTests", dependencies: ["YappingCore"]),
        .testTarget(name: "YappingToAPiAppTests", dependencies: ["YappingToAPiApp", "YappingCore"]),
        .testTarget(
            name: "YappingToAPiHelperTests",
            dependencies: ["YappingToAPiHelper"],
            path: "Tests/YappingToAPiHelperTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
