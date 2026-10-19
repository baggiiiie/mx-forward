import CoreServices
import Darwin
import Foundation
import MouseEngine

/// Install or remove the current user's login agent.
package enum AgentService {
    package static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(AgentIdentity.service).plist")
    }

    package static let controllerLockURL = ConfigJSON.defaultURL.deletingLastPathComponent()
        .appendingPathComponent("controller.lock")

    package static func installAndStart(appURL: URL) async throws {
        try await Task.detached {
            try serialized {
                let agentBundle = appURL.appendingPathComponent(
                    "Contents/Library/LoginItems/MX Forward Agent.app")
                let executable = agentBundle.appendingPathComponent("Contents/MacOS/MXForwardAgent")
                let manager = FileManager.default
                guard manager.isExecutableFile(atPath: executable.path) else {
                    throw IPCError("Build/open the bundled MX Forward.app to install the mouse agent")
                }
                // Register both bundles without launching or activating either app.
                for bundle in [appURL, agentBundle] {
                    let status = LSRegisterURL(bundle as CFURL, true)
                    guard status == noErr else {
                        throw IPCError("Could not register \(bundle.lastPathComponent): \(status)")
                    }
                }
                let logs = manager.homeDirectoryForCurrentUser.appendingPathComponent(
                    "Library/Logs/MX Forward")
                try manager.createDirectory(at: logs, withIntermediateDirectories: true)
                let definition: [String: Any] = [
                    "Label": AgentIdentity.service,
                    "ProgramArguments": [executable.path],
                    "MachServices": [AgentIdentity.service: true],
                    "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
                    "ExitTimeOut": 30, "ProcessType": "Interactive",
                    "LimitLoadToSessionType": "Aqua",
                    "StandardOutPath": logs.appendingPathComponent("agent.log").path,
                    "StandardErrorPath": logs.appendingPathComponent("agent-error.log").path,
                ]
                let job = "gui/\(getuid())/\(AgentIdentity.service)"
                let installed = (try? Data(contentsOf: plistURL)).flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil) as? NSDictionary
                }
                if isLoaded(job), installed?.isEqual(to: definition) == true {
                    try requireSuccess(["enable", job])
                    try requireSuccess(["kickstart", job])
                    return
                }
                if isLoaded(job) { try removeJob(job) }
                let data = try PropertyListSerialization.data(
                    fromPropertyList: definition, format: .xml, options: 0)
                try data.write(to: plistURL, options: .atomic)
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)
                try requireSuccess(["enable", job])
                try requireSuccess(["bootstrap", "gui/\(getuid())", plistURL.path])
            }
        }.value
    }

    package static func uninstall() async throws {
        try await Task.detached {
            try serialized {
                // The agent can uninstall itself, so remove startup before bootout kills it.
                if FileManager.default.fileExists(atPath: plistURL.path) {
                    try FileManager.default.removeItem(at: plistURL)
                }
                let job = "gui/\(getuid())/\(AgentIdentity.service)"
                if isLoaded(job) { try removeJob(job) }
            }
        }.value
    }

    private static func serialized<T>(_ operation: () throws -> T) throws -> T {
        let lock = try FileLock(url: plistURL.appendingPathExtension("lock"), wait: true)
        return try withExtendedLifetime(lock, operation)
    }

    private static func isLoaded(_ job: String) -> Bool {
        (try? run(["print", job]).0) == 0
    }

    private static func removeJob(_ job: String) throws {
        try requireSuccess(["bootout", job])
        let deadline = ContinuousClock.now + .seconds(35)
        while isLoaded(job) {
            guard ContinuousClock.now < deadline else {
                throw IPCError("The mouse agent is still shutting down")
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func requireSuccess(_ arguments: [String]) throws {
        let (status, output) = try run(arguments)
        guard status == 0 else { throw IPCError("launchctl \(arguments[0]) failed: \(output)") }
    }

    private static func run(_ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
