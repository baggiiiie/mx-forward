import AppKit
import ForwardCore

@MainActor
enum AppSettingsChecks {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw MouseError.message(message) }
    }

    static func run() throws {
        let legacy = Data(
            #"{"holdMilliseconds":650,"shortcut":{"keyCode":35,"modifiers":1179648,"keyLabel":"P"},"zoomSensitivity":3,"resumeMappings":true,"backClick":{"source":"none"},"thumbShortcuts":{"up":{"source":"none"}},"topClickAction":"none"}"#
                .utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
        var expectedButtons = ButtonMappings()
        expectedButtons.forward.hold = .shortcut(
            Shortcut(keyCode: 35, modifiers: 1_179_648, keyLabel: "P"))
        expectedButtons.forward.holdMilliseconds = 650
        expectedButtons.back.click = ButtonAction(.none)
        expectedButtons.thumb.up = ButtonAction(.none)
        expectedButtons.top.click = ButtonAction(.none)
        expectedButtons.top.zoomSpeed = 3
        try require(
            migrated.buttons == expectedButtons && migrated.resumeMappings && migrated.wheelAcceleration == 1
                && migrated.horizontalDirection == .unchanged,
            "Existing preferences did not migrate intact")
        print("PASS: preferences from older versions migrate to per-button click, hold, and drag actions")

        let custom = Shortcut(keyCode: 0, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "A")
        var preferences = migrated
        preferences.buttons.forward.click = .shortcut(custom)
        preferences.buttons.back.hold = ButtonAction(.missionControl)
        preferences.buttons.thumb.click = .shortcut(custom)
        preferences.buttons.top.left = ButtonAction(.desktopLeft)
        preferences.buttons.middle.enabled = true
        preferences.buttons.middle.down = ButtonAction(.appExpose)
        preferences.wheelAcceleration = 1.5
        preferences.horizontalDirection = .reversed
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        try require(restored == preferences, "Custom and cleared actions did not survive saving")
        try require(
            restored.hardwareConfiguration.movementControls == [.thumb, .top, .middle],
            "Only buttons with a drag action should freeze the pointer")

        var mapping = ButtonMapping()
        mapping.set(ButtonAction(.zoom), for: .up)
        try require(mapping.down.kind == .zoom, "Zoom must follow both drag directions")
        mapping.set(.shortcut(custom), for: .down)
        try require(mapping.up.isNone && mapping.down.shortcut == custom, "Leaving zoom must clear its pair")
        mapping.left = ButtonAction(.zoom)
        mapping.holdMilliseconds = 10
        try require(
            mapping.normalized().left.isNone && mapping.normalized().holdMilliseconds == 150,
            "Normalizing must drop sideways zoom and clamp timing")
        print("PASS: every button saves click, hold, and drag actions; zoom stays on up and down together")
        try runDragScrollChecks()
        preferences.wheelAcceleration = 0
        preferences.save()
        try require(Preferences.load().wheelAcceleration == 0, "Disabled acceleration did not persist")
        preferences.wheelAcceleration = 10
        preferences.save()
        try require(Preferences.load().wheelAcceleration == 2, "Acceleration exceeded its safe limit")
        print("PASS: wheel acceleration migrates, saves Off, and clamps to its supported range")
        try runConfigJSON(preferences.normalized())

        let recorder = RecorderButton()
        var recorded: [Shortcut] = []
        var transitions: [Bool] = []
        recorder.onRecord = { recorded.append($0) }
        recorder.onRecordingChanged = { transitions.append($0) }
        func key(
            _ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [], repeatKey: Bool = false
        ) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: repeatKey, keyCode: code)!
        }
        recorder.beginRecording()
        _ = recorder.performKeyEquivalent(with: key(0, "a", [.command, .shift], repeatKey: true))
        try require(recorded.isEmpty && transitions == [true], "Key repeat ended recording")
        _ = recorder.performKeyEquivalent(with: key(0, "a", [.command, .shift]))
        try require(
            recorded.last?.keyCode == 0 && recorded.last?.label == "⇧⌘A"
                && transitions == [true, false], "Recorder did not capture a shortcut and stop")
        recorder.beginRecording()
        recorder.keyDown(with: key(53, "\u{1b}"))
        try require(
            recorded.count == 1 && transitions == [true, false, true, false], "Escape changed the shortcut")
        recorder.beginRecording()
        recorder.keyDown(with: key(53, "\u{1b}", [.command]))
        try require(recorded.count == 2 && recorded.last?.keyCode == 53, "Modified Escape was not recordable")
        recorder.beginRecording()
        recorder.keyDown(with: key(126, "\u{f700}", [.control, .function, .numericPad]))
        try require(recorded.last?.label == "⌃↑", "Arrow-key hardware flags leaked into the shortcut label")
        recorder.beginRecording()
        recorder.isEnabled = false
        recorder.updateTitle()
        try require(transitions.last == false, "Disabling the recorder left mouse shortcuts suppressed")
        recorder.isEnabled = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60), styleMask: .borderless,
            backing: .buffered, defer: true)
        window.contentView = recorder
        recorder.beginRecording()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try require(
            transitions.last == false && recorded.count == 3, "Leaving the window did not cancel recording")
        print(
            "PASS: click-to-record captures keys, ignores repeats, and cancels on Escape, disable, or focus loss"
        )
    }

    private static func runDragScrollChecks() throws {
        var mapping = ButtonMapping()
        mapping.set(ButtonAction(.scroll), for: .left)
        try require(
            mapping.reportsMovement && ButtonSlot.directions.allSatisfy { mapping[$0].kind == .scroll },
            "Scroll must link all four directions and request raw movement")
        var scrolling = Preferences()
        scrolling.buttons.forward = mapping
        let scrollJSON = ConfigJSON.encode(scrolling)
        try require(
            try ConfigJSON.apply(scrollJSON, to: Preferences()) == scrolling.normalized(),
            "Drag scroll did not round-trip through JSON")
        mapping.set(ButtonAction(.zoom), for: .up)
        try require(
            mapping.verticalZoom && mapping.left.isNone && mapping.right.isNone,
            "Leaving scroll must clear its linked directions")
        for (action, phase) in [
            (DragScrollAction.begin, NSEvent.Phase.began), (.move(x: 12, y: -34), .changed),
            (.end, .ended), (.cancel, .cancelled),
        ] {
            guard let event = WheelOutput.dragEvent(action, at: CGPoint(x: 50, y: 60)),
                let decoded = NSEvent(cgEvent: event)
            else {
                throw MouseError.message("Could not decode drag scroll event")
            }
            try require(
                decoded.phase == phase && event.location == CGPoint(x: 50, y: 60),
                "Incorrect scroll phase")
            try require(decoded.hasPreciseScrollingDeltas, "Drag scroll must use pixel deltas")
            if case .move = action {
                try require(
                    decoded.scrollingDeltaX == 12 && decoded.scrollingDeltaY == -34,
                    "Drag scroll axes changed")
            }
        }
        for slot in ButtonSlot.directions {
            mapping.set(ButtonAction(.scroll), for: slot)
            mapping.set(ButtonAction(.missionControl), for: slot)
            try require(
                mapping[slot].kind == .missionControl && !mapping.dragScroll,
                "Leaving scroll kept a linked direction")
            try require(
                ButtonSlot.directions.filter { !mapping[$0].isNone }.count == 1,
                "Leaving scroll must clear the other directions")
        }
        for slot in [ButtonSlot.click, .hold] {
            mapping[slot] = ButtonAction(.scroll)
            try require(mapping.normalized()[slot].isNone, "Scroll must not be a press action")
        }
        for json in [
            #"{"buttons":{"forward":{"up":"scroll"}}}"#,
            #"{"buttons":{"forward":{"click":"scroll"}}}"#,
            #"{"buttons":{"forward":{"hold":"scroll"}}}"#,
        ] {
            do {
                _ = try ConfigJSON.apply(json, to: Preferences())
                throw MouseError.message("Invalid scroll configuration was accepted")
            } catch is ConfigError {}
        }
        var pointer = PointerOutput(
            at: CGPoint(x: 50, y: 60), displays: [CGRect(x: 0, y: 0, width: 100, height: 100)])
        let first = pointer.event(dx: 10, dy: -20)
        let second = pointer.event(dx: 10, dy: -20)
        try require(
            first?.location == CGPoint(x: 60, y: 40) && second?.location == CGPoint(x: 70, y: 20),
            "Queued pointer reports lost movement")
        try require(second?.getIntegerValueField(.mouseEventDeltaY) == -20, "Incorrect pointer delta")
        _ = pointer.event(dx: .max, dy: .min)
        try require(pointer.location == CGPoint(x: 99, y: 0), "Pointer escaped the display")
        _ = pointer.event(dx: -1, dy: 1)
        try require(pointer.location == CGPoint(x: 98, y: 1), "Pointer stuck at the display edge")
        var multipleDisplays = PointerOutput(
            at: CGPoint(x: 0, y: 50),
            displays: [
                CGRect(x: -100, y: 0, width: 100, height: 100),
                CGRect(x: 0, y: 0, width: 100, height: 100),
            ])
        _ = multipleDisplays.event(dx: -50, dy: 0)
        try require(multipleDisplays.location == CGPoint(x: -50, y: 50), "Pointer cannot cross displays")
        print("PASS: drag scroll links directions, validates JSON, and generates phased two-axis events")
        print("PASS: pointer reports accumulate and stay within connected displays")
    }

    private static func runConfigJSON(_ custom: Preferences) throws {
        var preferences = custom
        preferences.wheelSpeed = 0.25 + 0.05 * 18
        preferences.buttons.thumb.dragSensitivity = 0.25 + 0.05 * 7
        preferences.buttons.thumb.left = .shortcut(
            Shortcut(keyCode: 30, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "+"))
        var base = Preferences()
        base.resumeMappings = preferences.resumeMappings
        let text = ConfigJSON.encode(preferences)
        try require(
            ConfigJSON.document(from: try ConfigJSON.apply(text, to: base))
                == ConfigJSON.document(from: preferences),
            "JSON did not round-trip every setting")
        try require(
            try ConfigJSON.apply(text, to: preferences) == preferences, "An unchanged file changed settings")
        try require(text.contains(#""click": "cmd+a""#), "Shortcuts should be written as readable text")
        try require(text.contains(#""hold": "missionControl""#), "Actions should be written by name")
        try require(text.contains(#""label": "+""#), "Layout labels were lost")
        try require(
            text.range(of: #""forward""#)!.lowerBound < text.range(of: #""wheelButton""#)!.lowerBound,
            "Buttons should be written in a stable order")
        print("PASS: JSON configuration round-trips every button's actions and non-US shortcuts exactly")

        let cmd = CGEventFlags.maskCommand.rawValue
        let shift = CGEventFlags.maskShift.rawValue
        let parsed = try ShortcutText.parse("cmd+shift+]")
        try require(
            parsed.keyCode == 30 && parsed.modifiers == cmd | shift && parsed.label == "⇧⌘]", "Bad parse")
        try require(
            try ShortcutText.parse("⌘⇧T") == ShortcutText.parse("shift+cmd+t"), "Symbol modifiers failed")
        try require(try ShortcutText.parse("ctrl+up").label == "⌃↑", "Named keys failed")
        try require(ShortcutText.format(parsed) == "shift+cmd+]", "Shortcut text is not canonical")
        for invalid in ["cmd+foo", "hyper+a", "cmd+", ""] {
            try require((try? ShortcutText.parse(invalid)) == nil, "\"\(invalid)\" should be rejected")
        }
        print("PASS: shortcut text parses modifiers, symbols, and named keys, and rejects unknown names")

        let partial = try ConfigJSON.apply(
            #"{"buttons": {"back": {"click": "none", "hold": "cmd+w"}, "forward": {"click": "default"}}, "wheel": {"speedPercent": 5000, "mode": "freeSpin"}}"#,
            to: preferences)
        var expected = preferences
        expected.buttons.back.click = ButtonAction(.none)
        expected.buttons.back.hold = .shortcut(try ShortcutText.parse("cmd+w"))
        expected.buttons.forward.click = .shortcut(.forward)
        expected.wheelSpeed = 6
        expected.wheelMode = .freeSpin
        try require(partial == expected, "Partial JSON changed unrelated settings or skipped clamping")
        let failures: [(String, String)] = [
            (#"{"buttons": {"forward": {"left": "zoom"}}}"#, "buttons.forward.left"),
            (#"{"buttons": {"top": {"up": "missionControl"}}}"#, "set both to \"zoom\""),
            (#"{"wheel": {"mode": "spin"}}"#, "mode"),
            (#"{"buttons": {"top": {"enabled": "yes"}}}"#, "true or false"),
            (#"{"buttons": {"gesture": {"up": "cmd+nope"}}}"#, "nope"),
            ("{ not json", "Invalid JSON"),
        ]
        for (json, message) in failures {
            do {
                _ = try ConfigJSON.apply(json, to: preferences)
                throw MouseError.message("Accepted invalid JSON: \(json)")
            } catch let error as ConfigError {
                try require(error.message.contains(message), "Unclear error for \(json): \(error.message)")
            }
        }
        print("PASS: partial JSON updates only listed settings, clamps values, and explains invalid entries")
    }
}
