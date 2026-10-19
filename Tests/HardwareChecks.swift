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
        try AppSettingsChecks.run()
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
        for action: ButtonAction.Kind in [.missionControl, .appExpose, .desktopLeft, .desktopRight] {
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
        guard let (letterDown, _) = KeyboardOutput.events(for: Shortcut.forward) else {
            throw MouseError.message("Could not create browser navigation event")
        }
        try require(letterDown.flags == .maskCommand, "Arrow flags leaked onto browser navigation")
        print(
            "PASS: window navigation generates complete arrow-key presses without changing letter shortcuts")
        for pixels: Int32 in [-80, 40] {
            guard let event = WheelOutput.event(pixels: pixels), let native = NSEvent(cgEvent: event) else {
                throw MouseError.message("Could not create scroll event")
            }
            try require(
                native.type == .scrollWheel && native.hasPreciseScrollingDeltas
                    && native.scrollingDeltaY == CGFloat(pixels) && native.scrollingDeltaX == 0,
                "Scroll output lost pixel distance or changed horizontal scrolling")
        }
        print("PASS: macOS decodes precise vertical scroll events in both directions")
        for pixels: Int32 in [-80, 40] {
            guard let event = WheelOutput.event(pixels: 0, horizontal: pixels),
                let native = NSEvent(cgEvent: event)
            else { throw MouseError.message("Could not create horizontal scroll event") }
            try require(
                native.hasPreciseScrollingDeltas && native.scrollingDeltaX == CGFloat(pixels)
                    && native.scrollingDeltaY == 0,
                "Thumb-wheel output changed vertical scrolling or lost pixel distance")
        }
        let recoveryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        let recoveryURL = recoveryDirectory.appendingPathComponent("hardware-restore.json")
        let mouse = BoltMouse(recoveryURL: recoveryURL)
        var discoveryLog: [String] = []
        mouse.onLog = { discoveryLog.append($0) }
        mouse.onStatus = { discoveryLog.append($0) }
        try mouse.start()
        do {
            try await waitFor {
                mouse.rescan()
                return mouse.connection != nil
            }
        } catch {
            print(discoveryLog.joined(separator: "\n"))
            throw error
        }
        do {
            for mode in WheelMode.allCases {
                try await mouse.claim([], wheelMode: mode)
                try require(try await mouse.verifyClaim(), "Wheel-only claim was not confirmed")
                try require(
                    FileManager.default.fileExists(atPath: recoveryURL.path),
                    "Missing write-ahead recovery journal")
                try await mouse.release()
                try require(!mouse.claimed, "Wheel-only release failed")
                try require(
                    !FileManager.default.fileExists(atPath: recoveryURL.path),
                    "Successful release left a stale journal")
                print("PASS: main wheel \(mode.label) is applied, verified, and restored")
            }
            for inverted in [true, false, true] {
                try await mouse.claim([], horizontalInverted: inverted)
                try require(try await mouse.verifyClaim(), "Horizontal direction was not confirmed")
                try await mouse.release()
                try require(!mouse.claimed, "Horizontal direction was not restored")
            }
            print("PASS: horizontal direction reverses and restores the original native settings")
            for inverted: Bool? in [nil, true, false] {
                try await mouse.claim([], horizontalInverted: inverted, horizontalDiverted: true)
                try require(try await mouse.verifyClaim(), "Thumb-wheel diversion was not confirmed")
                try await mouse.release()
                try require(!mouse.claimed, "Thumb-wheel diversion was not restored")
            }
            print("PASS: thumb-wheel speed claims and restores native reporting in every direction")
            try await mouse.claim(
                [.forward], wheelMode: .ratchet, horizontalInverted: true, horizontalDiverted: true)
            try require(mouse.releaseImmediately(), "Immediate sleep-style restoration failed")
            try require(
                FileManager.default.fileExists(atPath: recoveryURL.path),
                "Unconfirmed restoration removed its recovery journal")
            let recovered = BoltMouse(recoveryURL: recoveryURL)
            try recovered.start()
            try await waitFor {
                recovered.rescan()
                return recovered.connection != nil && !recovered.recoveryPending
                    && !FileManager.default.fileExists(atPath: recoveryURL.path)
            }
            try require(!recovered.claimed, "Recovery left native controls claimed")
            print("PASS: a new controller verifies/restores an interrupted session's recovery journal")
        } catch {
            try? await mouse.release()
            throw error
        }
        var preferences = Preferences()
        preferences.wheelEnabled = true
        preferences.horizontalDirection = .reversed
        preferences.horizontalSpeed = 2
        preferences.wheelMode = .ratchet
        preferences.testMode = true
        preferences.resumeMappings = true
        preferences.save()
        let inputMouse = BoltMouse()
        let model = MouseEngine(mouse: inputMouse)
        var hardwareEvents: [String] = []
        let logToModel = inputMouse.onLog
        inputMouse.onLog = { event in
            hardwareEvents.append(event)
            logToModel(event)
        }
        do {
            try await waitFor { model.enabled }
            try require(model.connected && !model.needsRelease, "Startup claims were not confirmed")
            for name in preferences.controls.sorted().map(\.name) {
                try require(model.log.contains { $0.contains("Claimed \(name)") }, "Missing \(name) claim")
            }
            try require(model.log.contains { $0.contains("Claimed main wheel") }, "Missing wheel claim")
            try require(
                hardwareEvents.contains("Horizontal direction · Reversed"),
                "Missing horizontal direction setting")
            print("PASS: startup applies button mappings and both wheel settings")

            func claims(_ name: String) -> Int {
                hardwareEvents.filter { $0.contains("Claimed \(name)") }.count
            }
            let initialClaims = claims("Forward")
            model.preferences.wheelSpeed = 2
            model.preferences.horizontalSpeed = 3
            model.preferences.wheelAcceleration = 0.5
            model.preferences.buttons.top.zoomSpeed = 3
            model.preferences.buttons.forward.click = .shortcut(.back)
            model.preferences.buttons.thumb.click = ButtonAction(.none)
            try await Task.sleep(for: .milliseconds(300))
            try require(
                model.enabled && !model.busy && claims("Forward") == initialClaims,
                "Software settings unnecessarily disconnected the mouse")
            print("PASS: shortcuts, speeds, and acceleration change live without releasing mouse controls")
            inputMouse.onPress(.forward, true)
            let beforeRecording = model.log.count
            model.setRecordingShortcut(true)
            inputMouse.onPress(.forward, true)
            inputMouse.onPress(.forward, false)
            inputMouse.onPress(.back, true)
            inputMouse.onPress(.back, false)
            model.setRecordingShortcut(false)
            try require(model.log.count == beforeRecording, "Mouse shortcuts fired during recording")
            inputMouse.onPress(.forward, true)
            inputMouse.onPress(.forward, false)
            try require(
                model.lastAction.contains("Forward click → ⌘["), "Forward ignored its recorded click shortcut"
            )
            model.preferences.buttons.thumb.click = .shortcut(
                Shortcut(keyCode: 0, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "A"))
            model.preferences.buttons.thumb.up = ButtonAction(.none)
            inputMouse.onPress(.thumb, true)
            inputMouse.onPress(.thumb, false)
            try require(
                model.lastAction.contains("Thumb button click → ⌘A"), "Thumb click ignored its override")
            inputMouse.onPress(.thumb, true)
            inputMouse.onMovement(0, 0)
            inputMouse.onMovement(0, -200)
            inputMouse.onPress(.thumb, false)
            try require(
                model.lastAction.contains("Thumb button up → No action"), "Thumb up reused the click binding")
            inputMouse.onPress(.forward, true)
            let beforeEdit = model.log.count
            model.preferences.buttons.forward.holdMilliseconds = 600
            inputMouse.onPress(.forward, true)
            inputMouse.onPress(.forward, false)
            try require(model.log.count == beforeEdit, "An edited held button fired on release")
            print(
                "PASS: recording suppresses mouse actions; edits cancel held releases; thumb click and drag stay independent"
            )

            model.preferences.wheelMode = .freeSpin
            try await waitFor {
                model.enabled && !model.busy
                    && model.log.contains { $0.contains("Claimed main wheel · Free-spin") }
            }
            try require(model.preferences.resumeMappings, "Changing hardware settings lost active intent")
            print("PASS: wheel-mode changes automatically restore and reclaim the mouse")

            let oldBackClaims = claims("Back")
            let oldForwardClaims = claims("Forward")
            model.preferences.buttons.back.enabled = false
            try await waitFor { model.enabled && !model.busy && claims("Forward") > oldForwardClaims }
            try require(claims("Back") == oldBackClaims, "A disabled button was reclaimed")
            model.preferences.buttons.back.enabled = true
            try await waitFor { model.enabled && !model.busy && claims("Back") > oldBackClaims }
            print("PASS: feature toggles apply automatically without a manual Pause")

            let beforeDirectionChange = claims("Forward")
            model.preferences.horizontalDirection = .standard
            try await waitFor { model.enabled && !model.busy && claims("Forward") > beforeDirectionChange }
            try require(
                hardwareEvents.contains("Restored horizontal scrolling"),
                "Horizontal reversal stayed active after disabling it")
            let beforeReverse = hardwareEvents.filter { $0 == "Horizontal direction · Reversed" }.count
            model.preferences.horizontalDirection = .reversed
            try await waitFor {
                model.enabled && !model.busy
                    && hardwareEvents.filter { $0 == "Horizontal direction · Reversed" }.count > beforeReverse
            }
            print("PASS: horizontal direction changes live without a manual Pause")

            var empty = model.preferences
            for control in MouseControl.allCases { empty.buttons[control].enabled = false }
            empty.wheelEnabled = false
            empty.horizontalDirection = .unchanged
            empty.horizontalSpeed = 1
            model.preferences = empty
            try await waitFor { !model.enabled && !model.busy }
            try require(
                !model.needsRelease && model.preferences.resumeMappings,
                "Turning off every feature did not restore controls and preserve intent")
            model.preferences = preferences
            try await waitFor { model.enabled && !model.busy }
            print("PASS: disabling every feature restores native input; enabling one resumes automatically")

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
            model.preferences.wheelMode = .unchanged
            model.preferences.buttons.top.zoomSpeed = 4
            try await Task.sleep(for: .seconds(4))
            try require(!model.enabled, "Changing settings after an explicit Pause resumed mappings")
            print("PASS: explicit Pause stays paused")

            await model.enable()
            try require(model.enabled, "Could not re-enable for the quit check")
            let mayQuit = await model.shutdown()
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
