import AppKit
import MouseEngine
import AgentSupport

/// Headless regression entry point for the actual settings proxy, without a window
/// or the production launchd service. Run `swift run MXForward --check-proxy`.
@MainActor
enum ProxyChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await run()
                print("PASS: UI proxy sync, rapid edits, external changes, recording lease, close flush")
                exit(0)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw IPCError("Timed out waiting for proxy state") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func run() async throws {
        let engine = MouseEngine(initialPreferences: Preferences(), startsHardware: false, persistsSettings: false)
        let listener = NSXPCListener.anonymous()
        let server = AgentServer(engine: engine, listener: listener)
        server.start()
        let client = AgentConnection(endpoint: listener.endpoint)
        let proxy = AppModel(client: client, installService: false)
        try await wait { proxy.agentAvailable }
        for value in 25...200 { proxy.preferences.wheelSpeed = Double(value) / 100 }
        try await wait { !proxy.settingsPending && engine.preferences.wheelSpeed == 2 }
        // An external settings change must update the proxy, not be written back stale.
        engine.preferences.wheelSpeed = 1.75
        try await wait { proxy.preferences.wheelSpeed == 1.75 }
        proxy.setRecordingShortcut(true)
        try await wait { engine.isRecordingShortcut }
        proxy.preferences.wheelSpeed = 1.9
        await proxy.finish()
        guard engine.preferences.wheelSpeed == 1.9, !engine.isRecordingShortcut else {
            throw IPCError("Closing the UI lost settings or left recording suppressed")
        }
        guard await server.stop() else { throw IPCError("Test engine shutdown failed") }
    }
}
