// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PaolaGestionale",
    defaultLocalization: "it",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "PaolaCore", targets: ["PaolaCore"]),
        .executable(name: "PaolaGestionale", targets: ["PaolaApp"])
    ],
    targets: [
        .target(name: "PaolaCore"),
        .executableTarget(
            name: "PaolaApp",
            dependencies: ["PaolaCore"]
        ),
        .testTarget(
            name: "PaolaCoreTests",
            dependencies: ["PaolaCore"]
        ),
        .testTarget(
            name: "PaolaAppTests",
            dependencies: ["PaolaApp"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
