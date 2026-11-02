// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LumoCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LumoCore", targets: ["LumoCore"])],
    targets: [
        .target(name: "LumoCore", resources: [.process("Resources")]),
        .testTarget(name: "LumoCoreTests", dependencies: ["LumoCore"])
    ],
    swiftLanguageModes: [.v5]
)
