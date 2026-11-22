// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FastMusic",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FastMusic", targets: ["FastMusic"])],
    targets: [
        .executableTarget(name: "FastMusic"),
        .testTarget(name: "FastMusicTests", dependencies: ["FastMusic"])
    ],
    swiftLanguageModes: [.v5]
)
