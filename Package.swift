// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MXForward",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MXForward", targets: ["MXForward"]),
        .executable(name: "MXForwardAgent", targets: ["MXForwardAgent"]),
        .executable(name: "MXForwardHeadless", targets: ["HeadlessPrototype"]),
    ],
    targets: [
        .target(name: "ForwardCore"),
        .target(name: "MouseEngine", dependencies: ["ForwardCore"]),
        .target(name: "AgentSupport", dependencies: ["MouseEngine", "ForwardCore"]),
        .executableTarget(name: "MXForward", dependencies: ["ForwardCore", "MouseEngine", "AgentSupport"]),
        .executableTarget(name: "MXForwardAgent", dependencies: ["MouseEngine", "AgentSupport"]),
        .executableTarget(name: "HeadlessPrototype", dependencies: ["MouseEngine"]),
        .executableTarget(
            name: "AgentChecks", dependencies: ["MouseEngine", "AgentSupport", "ForwardCore"],
            path: "Tests/AgentChecks"),
        .executableTarget(
            name: "ForwardCoreChecks", dependencies: ["ForwardCore"], path: "Tests/ForwardCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
