// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MXForward",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MXForward", targets: ["MXForward"]),
        .executable(name: "MXForwardAgent", targets: ["MXForwardAgent"]),
    ],
    targets: [
        .target(name: "ForwardCore"),
        .target(name: "MouseEngine", dependencies: ["ForwardCore"]),
        .target(name: "AgentSupport", dependencies: ["MouseEngine", "ForwardCore"]),
        .target(name: "SettingsClient", dependencies: ["ForwardCore", "MouseEngine", "AgentSupport"]),
        .executableTarget(
            name: "MXForward", dependencies: ["ForwardCore", "MouseEngine", "SettingsClient"],
            resources: [.process("Resources")]),
        .executableTarget(name: "MXForwardAgent", dependencies: ["MouseEngine", "AgentSupport"]),
        .target(name: "CheckSupport", dependencies: ["AgentSupport"], path: "Tests/CheckSupport"),
        .executableTarget(
            name: "ProxyChecks",
            dependencies: ["SettingsClient", "MouseEngine", "AgentSupport", "CheckSupport"],
            path: "Tests/ProxyChecks"),
        .executableTarget(
            name: "AgentChecks",
            dependencies: ["MouseEngine", "AgentSupport", "ForwardCore", "CheckSupport"],
            path: "Tests/AgentChecks"),
        .executableTarget(
            name: "ForwardCoreChecks", dependencies: ["ForwardCore"], path: "Tests/ForwardCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
