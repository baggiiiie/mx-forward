// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MXForward",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MXForward", targets: ["MXForward"])],
    targets: [
        .target(name: "ForwardCore"),
        .executableTarget(name: "MXForward", dependencies: ["ForwardCore"]),
        .executableTarget(
            name: "ForwardCoreChecks", dependencies: ["ForwardCore"], path: "Tests/ForwardCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
