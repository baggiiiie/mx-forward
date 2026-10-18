import AppKit
import Darwin
import ForwardCore
import MouseEngine
import AgentSupport

@main
@MainActor
enum AgentChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await run()
                print("PASS: IPC validation, settings authority, recording leases, config isolation, locking, shutdown")
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

    private static func run() async throws {
        let request = AgentRequest(.settings, preferences: Preferences())
        let data = try JSONEncoder().encode(request)
        let decoded = try AgentCodec.decode(AgentRequest.self, from: data)
        try require(decoded.command == .settings, "Request round-trip failed")
        do {
            _ = try AgentCodec.decode(AgentRequest.self, from: Data(repeating: 32, count: AgentCodec.maximumBytes + 1))
            throw IPCError("Oversized request was accepted")
        } catch let error as IPCError { throw error } catch {}

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: ControllerLock? = try ControllerLock(directory: directory)
        do {
            _ = try ControllerLock(directory: directory)
            throw IPCError("Duplicate controller lock was accepted")
        } catch let error as IPCError { throw error } catch {}
        owner = nil
        let secondOwner = try ControllerLock(directory: directory)
        withExtendedLifetime((owner, secondOwner)) {}

        let url = directory.appendingPathComponent("config.json")
        let original = "{\"testMode\":true,\"wheel\":{\"speedPercent\":125}}"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let stored = UserDefaults.standard.data(forKey: Preferences.storageKey)
        let engine = MouseEngine(configURL: url, initialPreferences: Preferences(),
                                 startsHardware: false, persistsSettings: false)
        try require(engine.preferences.wheelSpeed == 1.25, "Initial config wasn't read")
        let listener = NSXPCListener.anonymous()
        let server = AgentServer(engine: engine, listener: listener)
        server.start()
        let first = AgentConnection(endpoint: listener.endpoint)
        let second = AgentConnection(endpoint: listener.endpoint)
        var response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.connected == false, "Offline engine connected to hardware")
        try require(response.state?.preferences.wheelSpeed == 1.25, "Snapshot lost settings")
        var settings = Preferences()
        settings.resumeMappings = true
        settings.wheelSpeed = 1000
        response = try await first.exchange(AgentRequest(.settings, preferences: settings))
        try require(response.state?.preferences.wheelSpeed == 6, "Agent didn't normalize settings")
        try require(response.state?.preferences.resumeMappings == false, "Stale client changed Enable/Pause")
        try require(try String(contentsOf: url, encoding: .utf8) == original, "Read-only mode wrote config")
        try require(UserDefaults.standard.data(forKey: Preferences.storageKey) == stored, "Read-only mode wrote defaults")
        response = try await first.exchange(AgentRequest(.enable))
        try require(response.error != nil && response.state?.enabled == false, "Offline Enable wasn't refused")
        var incompatible = AgentRequest(.snapshot)
        incompatible.version += 1
        response = try await first.exchange(incompatible)
        try require(response.error != nil, "Version mismatch wasn't refused")
        _ = try await first.exchange(AgentRequest(.recording, recording: true))
        response = try await second.exchange(AgentRequest(.recording, recording: true))
        try require(response.state?.recording == true, "Recording lease wasn't acquired")
        _ = try await first.exchange(AgentRequest(.recording, recording: false))
        response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.recording == true, "One UI cleared another UI's lease")
        second.close()
        for _ in 0..<20 {
            response = try await first.exchange(AgentRequest(.snapshot))
            if response.state?.recording == false { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(response.state?.recording == false, "Disconnected UI left recording suppressed")
        try "{\"wheel\":{\"speedPercent\":175}}".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1200))
        response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.preferences.wheelSpeed == 1.75, "Config file reload failed")
        first.close()
        let restored = await server.stop()
        try require(restored && !engine.connected && !engine.enabled, "Offline shutdown failed")
        await engine.enable()
        try require(!engine.enabled, "Shutdown engine re-enabled")
    }
}
