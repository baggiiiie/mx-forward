import Foundation
import Darwin

/// A per-user LaunchAgent: no root daemon, shell, or administrator privileges.
/// launchd owns restart/login behavior; quitting the settings UI doesn't stop it.
package enum AgentService {
    package static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(AgentIdentity.service).plist")
    }

    package static func installAndStart(appURL: URL) async throws {
        try await Task.detached {
            let executable = appURL.appendingPathComponent(
                "Contents/Library/LoginItems/MX Forward Agent.app/Contents/MacOS/MXForwardAgent")
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw IPCError("Build/open the bundled MX Forward.app to install the mouse agent")
            }
            let manager = FileManager.default
            let logs = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/MX Forward")
            try manager.createDirectory(at: logs, withIntermediateDirectories: true)
            try manager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": AgentIdentity.service,
                "ProgramArguments": [executable.path],
                "MachServices": [AgentIdentity.service: true],
                "RunAtLoad": true, "KeepAlive": true, "ThrottleInterval": 10,
                "ExitTimeOut": 30, "ProcessType": "Interactive",
                "LimitLoadToSessionType": "Aqua",
                "StandardOutPath": logs.appendingPathComponent("agent.log").path,
                "StandardErrorPath": logs.appendingPathComponent("agent-error.log").path,
            ]
            let domain = "gui/\(getuid())"
            let job = "\(domain)/\(AgentIdentity.service)"
            let old = (try? Data(contentsOf: plistURL)).flatMap {
                try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
            }
            let loaded = (try? run(["print", job]).0) == 0
            if loaded && (old?["ProgramArguments"] as? [String]) == [executable.path] { return }
            if loaded {
                let result = try run(["bootout", job])
                guard result.0 == 0 else { throw IPCError("Cannot stop old agent: \(result.1)") }
                try waitForRemoval(job)
            }
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)
            let enabled = try run(["enable", job])
            guard enabled.0 == 0 else { throw IPCError("Cannot enable mouse agent: \(enabled.1)") }
            let result = try run(["bootstrap", domain, plistURL.path])
            guard result.0 == 0 else { throw IPCError("Cannot start mouse agent: \(result.1)") }
        }.value
    }

    /// Used by the explicit uninstall action, never by window close or UI Quit.
    package static func uninstall() async throws {
        try await Task.detached {
            let job = "gui/\(getuid())/\(AgentIdentity.service)"
            // Remove startup first: this can also be called from the agent's menu,
            // and bootout will deliver SIGTERM to that very process.
            if FileManager.default.fileExists(atPath: plistURL.path) {
                try FileManager.default.removeItem(at: plistURL)
            }
            if (try? run(["print", job]).0) == 0 {
                let result = try run(["bootout", job])
                guard result.0 == 0 else { throw IPCError("Cannot stop agent: \(result.1)") }
                try waitForRemoval(job)
            }
        }.value
    }

    private static func waitForRemoval(_ job: String) throws {
        for _ in 0..<175 {
            if (try? run(["print", job]).0) != 0 { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw IPCError("The old mouse agent is still shutting down")
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
