import AppKit
import ForwardCore

@MainActor
enum AppSettingsChecks {
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw MouseError.message(message) }
    }

    static func run() throws {
        let legacy = Data(
            #"{"holdMilliseconds":650,"shortcut":{"keyCode":35,"modifiers":1179648,"keyLabel":"P"},"zoomSensitivity":2,"resumeMappings":true}"#
                .utf8)
        let migrated = try JSONDecoder().decode(Preferences.self, from: legacy)
        try require(
            migrated.holdMilliseconds == 650 && migrated.forwardHoldEnabled
                && migrated.shortcut?.keyCode == 35 && migrated.zoomSensitivity == 2
                && migrated.resumeMappings && migrated.forwardClick.source == .defaultShortcut
                && migrated.backClick.source == .defaultShortcut && migrated.thumbShortcuts.isEmpty
                && migrated.wheelAcceleration == 1 && migrated.horizontalDirection == .unchanged,
            "Existing preferences did not migrate intact")
        let custom = Shortcut(keyCode: 0, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "A")
        var preferences = migrated
        preferences.forwardClick = ShortcutMapping(source: .custom, shortcut: custom)
        preferences.backClick = ShortcutMapping(source: .none)
        preferences.thumbShortcuts["click"] = ShortcutMapping(source: .custom, shortcut: custom)
        preferences.thumbShortcuts["up"] = ShortcutMapping(source: .none)
        preferences.wheelAcceleration = 1.5
        preferences.horizontalDirection = .reversed
        preferences.topClickAction = .shortcut
        preferences.topClickShortcut = custom
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences))
        try require(restored == preferences, "Custom and cleared mappings did not survive saving")
        try require(
            restored.forwardClick.resolve(default: .forward) == custom
                && restored.backClick.resolve(default: .back) == nil
                && restored.thumbShortcut(.click) == custom && restored.thumbShortcut(.up) == nil,
            "A custom or cleared shortcut fell back to a preset")
        try require(
            ShortcutMapping().resolve(default: .back) == .back
                && ShortcutMapping().resolve(default: nil) == nil
                && ShortcutMapping(source: .custom, shortcut: custom).resolve(default: nil) == custom,
            "Defaults must follow system settings while custom shortcuts remain independent")
        print("PASS: existing preferences migrate and every custom/cleared shortcut persists independently")
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

    private static func runConfigJSON(_ custom: Preferences) throws {
        var preferences = custom
        preferences.wheelSpeed = 0.25 + 0.05 * 18
        preferences.thumbShortcuts["left"] = ShortcutMapping(
            source: .custom,
            shortcut: Shortcut(keyCode: 30, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "+"))
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
        try require(text.contains(#""label": "+""#), "Layout labels were lost")
        print("PASS: JSON configuration round-trips custom, cleared, and non-US shortcuts exactly")

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
            #"{"buttons": {"back": {"click": "none"}, "wheel": {"speedPercent": 5000, "mode": "freeSpin"}}}"#,
            to: preferences)
        var expected = preferences
        expected.backClick = ShortcutMapping(source: .none)
        expected.wheelSpeed = 6
        expected.wheelMode = .freeSpin
        try require(partial == expected, "Partial JSON changed unrelated settings or skipped clamping")
        let failures: [(String, String)] = [
            (#"{"buttons": {"forward": {"click": "smartZoom"}}}"#, "buttons.forward.click"),
            (#"{"buttons": {"wheel": {"mode": "spin"}}}"#, "mode"),
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
