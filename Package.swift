// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DJIMediaMover",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "DJIMediaMover", targets: ["DJIMediaMover"])],
    targets: [.executableTarget(name: "DJIMediaMover")]
)
