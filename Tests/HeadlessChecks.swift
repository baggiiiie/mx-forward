import AppKit

@main
@MainActor
enum HeadlessChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await run()
                print("PASS: headless isolation, config reload, disabled hardware, safe shutdown")
                exit(0)
            } catch {
                print("FAIL: \(error)")
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw MouseError.message(message) }
    }

    private static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.json")
        let original = "{\"testMode\":true,\"wheel\":{\"speedPercent\":125}}"
        try original.write(to: url, atomically: true, encoding: .utf8)
        let stored = UserDefaults.standard.data(forKey: Preferences.storageKey)
        let engine = AppModel(
            configURL: url, initialPreferences: Preferences(),
            startsHardware: false, persistsSettings: false)
        try require(engine.preferences.wheelSpeed == 1.25, "Initial config wasn't read")
        try engine.applyConfig("{\"wheel\":{\"speedPercent\":150}}")
        engine.rewriteConfigFile()
        try require(engine.preferences.wheelSpeed == 1.5, "In-memory config wasn't applied")
        try require(try String(contentsOf: url, encoding: .utf8) == original, "Read-only mode wrote config")
        try require(UserDefaults.standard.data(forKey: Preferences.storageKey) == stored, "Read-only mode wrote preferences")
        try "{\"wheel\":{\"speedPercent\":175}}".write(to: url, atomically: true, encoding: .utf8)
        try await Task.sleep(for: .milliseconds(1200))
        try require(engine.preferences.wheelSpeed == 1.75, "Config polling didn't reload edits")
        engine.preferences.resumeMappings = true
        engine.discover()
        await engine.enable()
        try await Task.sleep(for: .seconds(3))
        try require(!engine.connected && !engine.enabled && !engine.needsRelease, "Offline engine accessed hardware")
        let stopped = await engine.quitSafely(showAlert: false)
        try require(stopped, "Offline shutdown failed")
        let missing = directory.appendingPathComponent("missing.json")
        let missingEngine = AppModel(
            configURL: missing, initialPreferences: Preferences(),
            startsHardware: false, persistsSettings: false)
        missingEngine.rewriteConfigFile()
        try require(!FileManager.default.fileExists(atPath: missing.path), "Read-only mode created missing config")
    }
}
