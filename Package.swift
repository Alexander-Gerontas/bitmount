// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BitMount",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "BitMount", targets: ["BitMount"])
    ],
    targets: [
        .target(name: "BitMountCore"),
        .executableTarget(
            name: "BitMount",
            dependencies: ["BitMountCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "BitMountCoreTests",
            dependencies: ["BitMountCore"]
        ),
    ]
)
