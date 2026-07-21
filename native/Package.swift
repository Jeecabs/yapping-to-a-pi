// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "YappingToAPiNative",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "yapping-to-a-pi-helper", targets: ["YappingToAPiHelper"])
    ],
    targets: [
        .executableTarget(
            name: "YappingToAPiHelper",
            path: "Sources/YappingToAPiHelper"
        )
    ],
    swiftLanguageModes: [.v6]
)
