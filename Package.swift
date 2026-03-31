// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftBrave",
    platforms: [
        .iOS(.v15),
        .macCatalyst(.v15),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "BraveAdblock",
            targets: ["BraveAdblock"]
        ),
        .library(
            name: "BravePlaylist",
            targets: ["BravePlaylist"]
        )
    ],
    targets: [
        .binaryTarget(
                    name: "BraveAdblockCore",
                    url: "https://github.com/lake-of-fire/swift-brave/releases/download/binary-02c318768733/BraveAdblockCore.xcframework.zip",
                    checksum: "c767bc13b469f8b53df7f90cfd309e6ef8437c9e4a93f32cf2ee0c1eb9e978f8"
                ),
        .target(
            name: "BraveAdblock",
            dependencies: [
                "BraveAdblockCore",
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedLibrary("c++")
            ]
        ),
        .target(
            name: "BravePlaylist",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "BraveAdblockTests",
            dependencies: ["BraveAdblock"]
        ),
        .testTarget(
            name: "BravePlaylistTests",
            dependencies: ["BravePlaylist"]
        )
    ]
)
