import AppKit
import ForwardCore
import Foundation

@main
@MainActor
private enum HardwareChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            do {
                try await run()
                exit(0)
            } catch {
                print("FAIL: \(error.localizedDescription)")
                exit(1)
            }
        }
        NSApplication.shared.run()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw MouseError.message(message) }
    }

    private static func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(25)
        while !condition() {
            try require(ContinuousClock.now < deadline, "Timed out waiting for the mouse")
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func run() async throws {
        precondition(Bundle.main.bundleIdentifier != "local.baggie.mxforward")
        try require(
            WindowNavigationOutput.shortcut(.missionControl, hotkeys: nil)?.keyCode == 126,
            "Missing default Mission Control shortcut")
        try require(
            WindowNavigationOutput.shortcut(.missionControl, hotkeys: ["32": ["enabled": false]]) == nil,
            "Disabled Mission Control shortcut must be respected")
        let customized: [String: Any] = [
            "32": ["enabled": true, "value": ["type": "standard", "parameters": [0, 20, 1_310_720]]]
        ]
        let shortcut = WindowNavigationOutput.shortcut(.missionControl, hotkeys: customized)
        try require(
            shortcut?.keyCode == 20 && shortcut?.modifiers == 1_310_720, "Custom shortcut was ignored")
        print("PASS: window actions respect default, customized, and disabled macOS shortcuts")
        for action: ThumbGestureInterpreter.Action in [
            .missionControl, .appExpose, .desktopLeft, .desktopRight,
        ] {
            guard let shortcut = WindowNavigationOutput.shortcut(action, hotkeys: nil),
                let (down, up) = KeyboardOutput.events(for: shortcut)
            else { throw MouseError.message("Could not create window navigation events") }
            for event in [down, up] {
                try require(
                    event.flags.contains([.maskControl, .maskNumericPad, .maskSecondaryFn])
                        && event.getIntegerValueField(.keyboardEventKeycode) == Int64(shortcut.keyCode),
                    "System navigation needs complete arrow-key events")
            }
            try require(down.type == .keyDown && up.type == .keyUp, "Missing keyboard press or release")
        }
        guard let (letterDown, _) = KeyboardOutput.events(for: KeyboardOutput.forward) else {
            throw MouseError.message("Could not create browser navigation event")
        }
        try require(letterDown.flags == .maskCommand, "Arrow flags leaked onto browser navigation")
        print(
            "PASS: window navigation generates complete arrow-key presses without changing letter shortcuts")
        var preferences = Preferences()
        preferences.testMode = true
        preferences.resumeMappings = true
        preferences.save()
        let model = AppModel()
        do {
            try await waitFor { model.enabled }
            try require(model.connected && !model.needsRelease, "Startup claims were not confirmed")
            for name in preferences.controls.sorted().map(\.name) {
                try require(model.log.contains { $0.contains("Claimed \(name)") }, "Missing \(name) claim")
            }
            print("PASS: startup discovers and claims all selected buttons")

            let notifications = NSWorkspace.shared.notificationCenter
            notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
            await model.enable()
            try require(!model.enabled, "An Enable queued during sleep must be ignored")
            try require(model.preferences.resumeMappings, "Sleep lost the resume setting")
            print("PASS: Enable cannot reclaim buttons during sleep")
            try await Task.sleep(for: .seconds(4))
            try require(!model.enabled, "Mappings resumed before wake")
            print("PASS: mappings remain suspended until wake")

            notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
            try await waitFor { model.enabled }
            print("PASS: wake rediscovers and resumes mappings")

            await model.pause()
            try require(
                !model.enabled && !model.preferences.resumeMappings, "Pause retained the resume setting")
            try await Task.sleep(for: .seconds(4))
            try require(!model.enabled, "Explicit Pause resumed automatically")
            print("PASS: explicit Pause stays paused")

            await model.enable()
            try require(model.enabled, "Could not re-enable for the quit check")
            let mayQuit = await model.quitSafely()
            try require(
                mayQuit && !model.enabled && !model.needsRelease, "Quit failed to restore the buttons")
            try require(Preferences.load().resumeMappings, "Quit lost the saved resume setting")
            print("PASS: quit restores buttons and preserves resume for the next launch")
        } catch {
            print(model.log.joined(separator: "\n"))
            await model.pause()
            throw error
        }
    }
}
