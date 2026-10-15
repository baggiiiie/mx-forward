import AppKit
import ForwardCore

enum WindowNavigationOutput {
    static func label(_ action: ThumbGestureInterpreter.Action) -> String {
        switch action {
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .desktopLeft: return "Desktop left"
        case .desktopRight: return "Desktop right"
        }
    }

    static func send(_ action: ThumbGestureInterpreter.Action) -> Bool {
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        guard let shortcut = shortcut(action, hotkeys: hotkeys) else { return false }
        return KeyboardOutput.send(shortcut)
    }

    static func shortcut(
        _ action: ThumbGestureInterpreter.Action, hotkeys: [String: Any]?
    ) -> Shortcut? {
        let id: String
        let defaultKey: UInt16
        switch action {
        case .missionControl: (id, defaultKey) = ("32", 126)
        case .appExpose: (id, defaultKey) = ("33", 125)
        case .desktopLeft: (id, defaultKey) = ("79", 123)
        case .desktopRight: (id, defaultKey) = ("81", 124)
        }
        let entry = hotkeys?[id] as? [String: Any]
        guard entry?["enabled"] as? Bool != false else { return nil }
        let keyCode: UInt16
        let modifiers: UInt64
        if let stored = entry?["value"] {
            guard let value = stored as? [String: Any], value["type"] as? String == "standard",
                let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3,
                let key = UInt16(exactly: parameters[1].intValue), key < 128
            else { return nil }
            keyCode = key
            modifiers = parameters[2].uint64Value
        } else {
            keyCode = defaultKey
            modifiers = CGEventFlags.maskControl.rawValue
        }
        return Shortcut(keyCode: keyCode, modifiers: modifiers, keyLabel: label(action))
    }
}
