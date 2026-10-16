// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LvLianCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LvLianCore", targets: ["LvLianCore"])],
    targets: [
        .target(name: "LvLianCore", path: "LvLian/Core"),
        .testTarget(name: "LvLianCoreTests", dependencies: ["LvLianCore"], path: "Tests/LvLianCoreTests")
    ]
)
