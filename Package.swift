// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediaCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MediaCore", targets: ["MediaCore"])],
    targets: [
        .target(name: "MediaCore", path: "Shared"),
        .testTarget(name: "MediaCoreTests", dependencies: ["MediaCore"], path: "Tests/MediaCoreTests")
    ]
)
