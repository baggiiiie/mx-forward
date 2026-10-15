import AppKit
import ForwardCore

enum WindowNavigationOutput {
    static func label(_ action: ThumbGestureInterpreter.Action) -> String {
        switch action {
        case .click, .up: return "Mission Control"
        case .down: return "App Exposé"
        case .left: return "Desktop left"
        case .right: return "Desktop right"
        }
    }

    static func currentShortcut(_ action: ThumbGestureInterpreter.Action) -> Shortcut? {
        let hotkeys = UserDefaults(suiteName: "com.apple.symbolichotkeys")?
            .dictionary(forKey: "AppleSymbolicHotKeys")
        return shortcut(action, hotkeys: hotkeys)
    }

    static func shortcut(
        _ action: ThumbGestureInterpreter.Action, hotkeys: [String: Any]?
    ) -> Shortcut? {
        let id: String
        let defaultKey: UInt16
        switch action {
        case .click, .up: (id, defaultKey) = ("32", 126)
        case .down: (id, defaultKey) = ("33", 125)
        case .left: (id, defaultKey) = ("79", 123)
        case .right: (id, defaultKey) = ("81", 124)
        }
        let entry = hotkeys?[id] as? [String: Any]
        guard entry?["enabled"] as? Bool != false else { return nil }
        let keyCode: UInt16
        let modifiers: UInt64
        var characters: String?
        if let stored = entry?["value"] {
            guard let value = stored as? [String: Any], value["type"] as? String == "standard",
                let parameters = value["parameters"] as? [NSNumber], parameters.count >= 3,
                let key = UInt16(exactly: parameters[1].intValue), key < 128
            else { return nil }
            keyCode = key
            modifiers = parameters[2].uint64Value
            if let scalar = UnicodeScalar(parameters[0].uint32Value), scalar.value >= 32,
                scalar.value < 0xF700
            {
                characters = String(scalar)
            }
        } else {
            keyCode = defaultKey
            modifiers = CGEventFlags.maskControl.rawValue
        }
        return Shortcut(
            keyCode: keyCode, modifiers: modifiers,
            keyLabel: Shortcut.keyName(keyCode, characters: characters))
    }
}
