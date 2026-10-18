import AgentSupport
import AppKit
import CheckSupport
import MouseEngine
import SettingsClient

@main
@MainActor
enum ProxyChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await checkSyncAndRecording()
                try await checkInFlightEdits()
                try await checkFailedSave()
                try await checkCloseWithoutEdits()
                print(
                    "PASS: UI sync, in-flight Undo, concurrent edits, failed-save protection, recording, close"
                )
                exit(0)
            } catch {
                fputs("FAIL: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw IPCError(message) }
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw IPCError("Timed out waiting for proxy state") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func checkSyncAndRecording() async throws {
        let engine = MouseEngine(
            initialPreferences: Preferences(), startsHardware: false, persistsSettings: false)
        let listener = NSXPCListener.anonymous()
        let server = AgentServer(engine: engine, listener: listener)
        server.start()
        let client = AgentConnection(endpoint: listener.endpoint)
        let proxy = SettingsModel(client: client, installService: false)
        try await wait { proxy.agentAvailable }
        for value in 25...200 { proxy.preferences.wheelSpeed = Double(value) / 100 }
        try await wait { !proxy.settingsDirty && engine.preferences.wheelSpeed == 2 }
        engine.preferences.wheelSpeed = 1.75
        try await wait { proxy.preferences.wheelSpeed == 1.75 }
        proxy.setRecordingShortcut(true)
        try await wait { engine.isRecordingShortcut }
        client.close()
        try await wait { !engine.isRecordingShortcut }
        try await wait { engine.isRecordingShortcut }
        proxy.preferences.wheelSpeed = 1.9
        engine.preferences.resumeMappings = true
        try require(await proxy.finish(), "Closing the UI failed to save settings")
        try await wait { !engine.isRecordingShortcut }
        try require(engine.preferences.wheelSpeed == 1.9, "Closing the UI lost settings")
        try require(engine.preferences.resumeMappings, "Closing the UI changed the resume choice")
        try require(await server.stop(), "Test engine shutdown failed")
    }

    private static func checkInFlightEdits() async throws {
        let engine = MouseEngine(
            initialPreferences: Preferences(), startsHardware: false, persistsSettings: false)
        let server = TestAgent { request in
            if request.command == .settings, let base = request.basePreferences,
                let edited = request.preferences
            {
                engine.preferences = engine.preferences.applyingEdits(from: base, to: edited)
            }
            return try AgentCodec.encode(AgentResponse(state: AgentState(engine)))
        }
        server.hold = { $0.command == .settings }
        let proxy = SettingsModel(client: AgentConnection(endpoint: server.endpoint), installService: false)
        try await wait { proxy.agentAvailable }
        proxy.preferences.wheelSpeed = 2
        try await wait { server.heldCount == 1 }
        proxy.preferences.wheelSpeed = 1
        engine.preferences.buttons.forward.holdMilliseconds = 600
        server.hold = { _ in false }
        server.releaseReplies()
        try await wait { !proxy.settingsDirty && engine.preferences.wheelSpeed == 1 }
        try require(
            engine.preferences.buttons.forward.holdMilliseconds == 600, "UI overwrote a concurrent edit")
        try require(
            proxy.preferences.buttons.forward.holdMilliseconds == 600, "UI missed the concurrent edit")
        try require(await proxy.finish(), "Undo couldn't be saved on close")
        server.stop()
        _ = await engine.shutdown()
    }

    private static func checkFailedSave() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let url = directory.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let name = "mx-forward-proxy-check.\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: name) else {
            throw IPCError("Could not open test preferences")
        }
        defer { store.removePersistentDomain(forName: name) }
        let engine = MouseEngine(
            configURL: url, initialPreferences: Preferences(),
            startsHardware: false, preferenceStore: store)
        let listener = NSXPCListener.anonymous()
        let server = AgentServer(engine: engine, listener: listener)
        server.start()
        let proxy = SettingsModel(client: AgentConnection(endpoint: listener.endpoint), installService: false)
        try await wait { proxy.agentAvailable }
        proxy.preferences.wheelSpeed = 2
        try require(!(await proxy.finish()), "UI exited after a failed save")
        try require(
            proxy.settingsDirty && proxy.preferences.wheelSpeed == 2, "Failed save discarded local edits")
        try require(engine.preferences.wheelSpeed == 1, "Failed save changed the active settings")
        try require(proxy.status.contains("Could not save settings"), "Failed save wasn't explained")
        try FileManager.default.removeItem(at: url)
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        try await wait { !proxy.settingsDirty }
        try require(await proxy.finish(), "UI couldn't close after repairing the config")
        try require(engine.preferences.wheelSpeed == 2, "Retry lost the edit")
        _ = await server.stop()
    }

    private static func checkCloseWithoutEdits() async throws {
        let server = TestAgent { _ in try AgentCodec.encode(AgentResponse(error: "test")) }
        server.hold = { _ in true }
        let proxy = SettingsModel(client: AgentConnection(endpoint: server.endpoint), installService: false)
        try await wait { server.heldCount == 1 }
        try require(await proxy.finish(), "An idle UI couldn't close while the agent was unresponsive")
        server.stop()
    }
}
