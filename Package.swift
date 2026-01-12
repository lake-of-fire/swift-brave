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
                    url: "https://github.com/lake-of-fire/swift-brave/releases/download/binary-34fee33100a7/BraveAdblockCore.xcframework.zip",
                    checksum: "2bc32d3c92f23939c27bf83b46da13d2acbbfd436169ec76881fb4ee5bce78d6"
                )
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
