import AgentSupport
import AppKit
import CheckSupport
import ForwardCore
import MouseEngine

@main
@MainActor
enum AgentChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try checkDragScrollPointer()
                try checkCodecAndLock()
                try await checkConnectionLifecycle()
                try await checkPreferencesStore()
                try await checkServer()
                print(
                    "PASS: IPC limits, cancellation, close/reconnect, settings merge, recording, config, shutdown"
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

    private static func expectFailure(_ message: String, _ operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw IPCError(message)
    }

    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw IPCError("Timed out waiting for a test reply") }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func checkDragScrollPointer() throws {
        var pointer = PointerOutput(
            at: CGPoint(x: 50, y: 60),
            displays: [CGRect(x: 0, y: 0, width: 200, height: 200)])
        let reports: [(Int16, Int16, CGPoint)] = [
            (10, -20, CGPoint(x: 60, y: 40)),
            (10, -20, CGPoint(x: 70, y: 20)),
            (.max, .min, CGPoint(x: 199, y: 0)),
            (-1, 1, CGPoint(x: 198, y: 1)),
        ]
        let phases: [(DragScrollAction, NSEvent.Phase)] = [
            (.begin, .began), (.move(x: 12, y: -34), .changed),
            (.end, .ended), (.cancel, .cancelled),
        ]
        // Build events without posting them, as if macOS hasn't processed them yet.
        for (dx, dy, expected) in reports {
            guard let movement = pointer.event(dx: dx, dy: dy) else {
                throw IPCError("Could not create pointer event")
            }
            try require(
                movement.location == expected && pointer.location == expected,
                "Queued pointer movement lost distance or escaped the display")
            for (action, phase) in phases {
                guard let scroll = pointer.scrollEvent(action), let native = NSEvent(cgEvent: scroll) else {
                    throw IPCError("Could not create drag scroll event")
                }
                try require(
                    scroll.location == expected,
                    "Scroll would pull the cursor away from its replayed position")
                try require(native.phase == phase, "Drag scroll phase changed")
                try require(native.hasPreciseScrollingDeltas, "Drag scroll lost pixel precision")
                let moving = phase == .changed
                try require(
                    native.scrollingDeltaX == (moving ? 12 : 0)
                        && native.scrollingDeltaY == (moving ? -34 : 0),
                    "Drag scroll deltas changed")
            }
        }
        print("PASS: drag scroll follows queued pointer movement, including display edges and all phases")
    }

    private static func checkCodecAndLock() throws {
        let data = try AgentCodec.encode(AgentRequest(.snapshot))
        let decoded = try AgentCodec.decode(AgentRequest.self, from: data)
        try require(decoded.command == .snapshot, "Request round-trip failed")
        try expectFailure("Oversized request was accepted") {
            _ = try AgentCodec.decode(
                AgentRequest.self, from: Data(repeating: 32, count: AgentCodec.maximumBytes + 1))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("controller.lock")
        var owner: FileLock? = try FileLock(url: url)
        try withExtendedLifetime(owner) {
            try expectFailure("Duplicate controller lock was accepted") { _ = try FileLock(url: url) }
        }
        owner = nil
        let nextOwner = try FileLock(url: url)
        withExtendedLifetime(nextOwner) {}
    }

    private static func checkConnectionLifecycle() async throws {
        let server = TestAgent { _ in try AgentCodec.encode(AgentResponse(error: "test reply")) }
        defer { server.stop() }
        server.hold = { _ in true }
        let client = AgentConnection(endpoint: server.endpoint)
        var finished = false
        let closed = Task {
            defer { finished = true }
            return try await client.exchange(AgentRequest(.snapshot))
        }
        var otherFinished = false
        let other = Task {
            defer { otherFinished = true }
            return try await client.exchange(AgentRequest(.snapshot))
        }
        try await wait { server.heldCount == 2 }
        client.close()
        try await wait { finished && otherFinished }
        if case .success = await closed.result {
            throw IPCError("Closing the connection succeeded unexpectedly")
        }
        if case .success = await other.result {
            throw IPCError("Closing left another request running")
        }
        server.hold = { _ in false }
        let reconnected = Task { try await client.exchange(AgentRequest(.snapshot)) }
        server.releaseReplies()
        try require(
            try await reconnected.value.error == "test reply", "A late reply broke the new connection")

        server.hold = { _ in true }
        finished = false
        let cancelled = Task {
            defer { finished = true }
            return try await client.exchange(AgentRequest(.snapshot))
        }
        try await wait { server.heldCount == 1 }
        cancelled.cancel()
        try await wait { finished }
        guard case .failure(let cancellation) = await cancelled.result, cancellation is CancellationError
        else {
            throw IPCError("Task cancellation wasn't propagated")
        }
        server.releaseReplies()
        client.close()

        let shortLived = AgentConnection(endpoint: server.endpoint, requestTimeout: .milliseconds(500))
        do {
            _ = try await shortLived.exchange(AgentRequest(.snapshot))
            throw IPCError("Missing reply didn't time out")
        } catch {
            try require(
                error.localizedDescription.contains("timed out"), "Unexpected timeout error: \(error)")
        }
        server.hold = { _ in false }
        _ = try await shortLived.exchange(AgentRequest(.snapshot))
        server.releaseReplies()
        shortLived.close()
    }

    private static func checkPreferencesStore() async throws {
        let name = "mx-forward-check.\(UUID().uuidString)"
        guard let store = UserDefaults(suiteName: name) else {
            throw IPCError("Could not create test preferences")
        }
        defer { store.removePersistentDomain(forName: name) }
        var preferences = Preferences()
        preferences.wheelSpeed = 2.75
        preferences.save(defaults: store)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let target = directory.appendingPathComponent("dotfiles.json")
        try #"{"wheel":{"speedPercent":275}}"#.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        let engine = MouseEngine(configURL: url, startsHardware: false, preferenceStore: store)
        try require(engine.preferences.wheelSpeed == 2.75, "Engine ignored its preference store")
        let original = try String(contentsOf: url, encoding: .utf8)
        engine.preferences.resumeMappings = true
        try require(
            try String(contentsOf: url, encoding: .utf8) == original,
            "Enable/Pause rewrote an unchanged partial config")
        engine.preferences.horizontalSpeed = 2
        let saved = try ConfigJSON.apply(String(contentsOf: url, encoding: .utf8), to: Preferences())
        try require(saved.horizontalSpeed == 2, "New thumb-wheel speed was omitted from an older JSON file")
        try require(Preferences.load(defaults: store).horizontalSpeed == 2, "Thumb-wheel speed was not saved")
        try require(
            try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == target.path,
            "Saving replaced the config symlink")
        let targetSettings = try ConfigJSON.apply(
            String(contentsOf: target, encoding: .utf8), to: Preferences())
        try require(targetSettings.horizontalSpeed == 2, "Saving did not update the symlink target")
        try #"{"wheel":{"speedPercent":150}}"#.write(to: target, atomically: true, encoding: .utf8)
        try await wait { engine.preferences.wheelSpeed == 1.5 }
        _ = await engine.shutdown()
    }

    private static func checkServer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let original = "{\"testMode\":true,\"wheel\":{\"speedPercent\":125}}"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let stored = UserDefaults.standard.data(forKey: Preferences.storageKey)
        let engine = MouseEngine(
            configURL: url, initialPreferences: Preferences(),
            startsHardware: false, persistsSettings: false)
        let listener = NSXPCListener.anonymous()
        let server = AgentServer(engine: engine, listener: listener)
        server.start()
        let first = AgentConnection(endpoint: listener.endpoint)
        let second = AgentConnection(endpoint: listener.endpoint)
        var response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.connected == false, "Offline engine connected to hardware")
        try require(
            response.state?.accessibility == false && response.state?.inputMonitoring == false,
            "Offline engine queried the host's input permissions")
        try require(response.state?.preferences.wheelSpeed == 1.25, "Snapshot lost settings")
        let base = engine.preferences
        var edited = base
        edited.resumeMappings = true
        edited.wheelSpeed = 1000
        engine.preferences.buttons.forward.holdMilliseconds = 600
        response = try await first.exchange(
            AgentRequest(.settings, preferences: edited, basePreferences: base))
        try require(response.state?.preferences.wheelSpeed == 6, "Agent didn't normalize settings")
        try require(
            response.state?.preferences.buttons.forward.holdMilliseconds == 600,
            "Stale UI overwrote another setting")
        try require(response.state?.preferences.resumeMappings == false, "Stale UI changed Enable/Pause")
        try require(try String(contentsOf: url, encoding: .utf8) == original, "Read-only mode wrote config")
        try require(
            UserDefaults.standard.data(forKey: Preferences.storageKey) == stored,
            "Read-only mode wrote defaults")
        let nextBase = engine.preferences
        var nextEdit = nextBase
        nextEdit.buttons.back.holdMilliseconds = 700
        try "{\"wheel\":{\"speedPercent\":175}}".write(to: url, atomically: true, encoding: .utf8)
        response = try await first.exchange(
            AgentRequest(.settings, preferences: nextEdit, basePreferences: nextBase))
        try require(response.state?.preferences.wheelSpeed == 1.75, "UI save overwrote a pending file edit")
        try require(
            response.state?.preferences.buttons.back.holdMilliseconds == 700, "File reload lost the UI edit")
        response = try await first.exchange(AgentRequest(.settings, preferences: edited))
        try require(response.error != nil, "Settings without a baseline were accepted")
        response = try await first.exchange(AgentRequest(.enable))
        try require(
            response.error != nil && response.state?.enabled == false, "Offline Enable wasn't refused")
        var incompatible = AgentRequest(.snapshot)
        incompatible.version += 1
        response = try await first.exchange(incompatible)
        try require(response.error != nil, "Version mismatch wasn't refused")
        engine.lastAction = String(repeating: "x", count: AgentCodec.maximumBytes)
        response = try await first.exchange(AgentRequest(.snapshot))
        try require(
            response.error?.contains("too large") == true,
            "Oversized state didn't produce a valid error reply")
        engine.lastAction = "test"

        _ = try await first.exchange(AgentRequest(.recording, recording: true))
        response = try await second.exchange(AgentRequest(.recording, recording: true))
        try require(response.state?.recording == true, "Recording wasn't suppressed")
        _ = try await first.exchange(AgentRequest(.recording, recording: false))
        response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.recording == true, "One UI ended another UI's recording")
        second.close()
        for _ in 0..<20 {
            response = try await first.exchange(AgentRequest(.snapshot))
            if response.state?.recording == false { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        try require(response.state?.recording == false, "Disconnected UI left recording suppressed")
        try "{\"wheel\":{\"speedPercent\":190}}".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1200))
        response = try await first.exchange(AgentRequest(.snapshot))
        try require(response.state?.preferences.wheelSpeed == 1.9, "Config file reload failed")
        first.close()
        let restored = await server.stop()
        try require(restored && !engine.connected && !engine.enabled, "Offline shutdown failed")
        await engine.enable()
        try require(!engine.enabled, "Shutdown engine re-enabled")
    }
}
