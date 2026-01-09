// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftBrave",
    platforms: [
        .iOS(.v15),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BraveAdblock",
            targets: ["BraveAdblock"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "BraveAdblockCore",
            url: "https://github.com/lake-of-fire/swift-brave/releases/download/binary-058baa22bb9c/BraveAdblockCore.xcframework.zip",
            checksum: "ef04b2cec392c2b5b0b2c2bdc64ebbb45658e3f4aff7cdebb47de708b003dff4"
        ),
        .target(
            name: "BraveAdblock",
            dependencies: ["BraveAdblockCore"],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "BraveAdblockTests",
            dependencies: ["BraveAdblock"]
        )
    ]
)
