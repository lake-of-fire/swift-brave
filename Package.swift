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
            url: "https://github.com/lake-of-fire/swift-brave/releases/download/binary-d0267e62aaae/BraveAdblockCore.xcframework.zip",
            checksum: "3030565300a0a1cd5d48302d39487a0ad965beb191f5b863a83b4f8c93be6930"
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
