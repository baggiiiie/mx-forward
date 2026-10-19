import CoreGraphics
import ForwardCore
import Foundation

/// The JSON config file. Every button has the same keys; missing keys keep their current value.
struct ConfigDocument: Codable, Equatable {
    var testMode: Bool?
    var buttons: Buttons?
    var wheel: Wheel?
    var thumbWheel: ThumbWheel?

    struct Buttons: Codable, Equatable {
        var forward: Button?
        var back: Button?
        var gesture: Button?
        var top: Button?
        var wheelButton: Button?

        /// JSON names in file order.
        static let names: [(String, MouseControl)] = [
            ("forward", .forward), ("back", .back), ("gesture", .thumb), ("top", .top),
            ("wheelButton", .middle),
        ]

        subscript(_ control: MouseControl) -> Button? {
            get {
                switch control {
                case .forward: return forward
                case .back: return back
                case .thumb: return gesture
                case .top: return top
                case .middle: return wheelButton
                }
            }
            set {
                switch control {
                case .forward: forward = newValue
                case .back: back = newValue
                case .thumb: gesture = newValue
                case .top: top = newValue
                case .middle: wheelButton = newValue
                }
            }
        }
    }

    struct Button: Codable, Equatable {
        var enabled: Bool?
        var click: ConfigAction?
        var hold: ConfigAction?
        var up: ConfigAction?
        var down: ConfigAction?
        var left: ConfigAction?
        var right: ConfigAction?
        var holdDelayMs: Double?
        var dragSensitivityPercent: Double?
        var zoomSpeedPercent: Double?

        subscript(_ slot: ButtonSlot) -> ConfigAction? {
            switch slot {
            case .click: return click
            case .hold: return hold
            case .up: return up
            case .down: return down
            case .left: return left
            case .right: return right
            }
        }
    }

    struct Wheel: Codable, Equatable {
        var enabled: Bool?
        var speedPercent: Double?
        var accelerationPercent: Double?
        var natural: Bool?
        var mode: WheelMode?
    }

    struct ThumbWheel: Codable, Equatable {
        var direction: HorizontalDirection?
        var speedPercent: Double?
    }
}

/// An action name such as `"missionControl"`, `"none"`, or `"default"`, or a shortcut such as `"cmd+shift+]"`.
/// Shortcuts that can't be written as text use `{"keyCode": 30, "modifiers": ["cmd"], "label": "+"}`.
enum ConfigAction: Codable, Equatable {
    /// The button's built-in action for that slot. Only read, never written.
    case `default`
    case action(ButtonAction)

    private struct ShortcutObject: Codable {
        var keyCode: UInt16
        var modifiers: [String]?
        var label: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .action(ButtonAction(.none))
        } else if let text = try? container.decode(String.self) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            func named(_ name: String) -> Bool { name.caseInsensitiveCompare(trimmed) == .orderedSame }
            if named("default") {
                self = .default
            } else if let kind = ButtonAction.Kind.allCases.first(where: {
                $0 != .shortcut && named($0.rawValue)
            }) {
                self = .action(ButtonAction(kind))
            } else {
                do { self = .action(.shortcut(try ShortcutText.parse(trimmed))) } catch {
                    throw DecodingError.dataCorruptedError(
                        in: container, debugDescription: error.localizedDescription)
                }
            }
        } else {
            let object = try container.decode(ShortcutObject.self)
            var modifiers: UInt64 = 0
            for name in object.modifiers ?? [] {
                guard let flag = ShortcutText.modifier(name) else {
                    throw DecodingError.dataCorruptedError(
                        in: container, debugDescription: "Unknown modifier \"\(name)\"")
                }
                modifiers |= flag
            }
            self = .action(
                .shortcut(
                    Shortcut(
                        keyCode: object.keyCode, modifiers: modifiers,
                        keyLabel: object.label
                            ?? Shortcut.keyName(
                                object.keyCode, characters: ShortcutText.name(for: object.keyCode)))))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .default: try container.encode("default")
        case .action(let action):
            guard action.kind == .shortcut else { return try container.encode(action.kind.rawValue) }
            guard let shortcut = action.shortcut else { return try container.encode("none") }
            if let text = ShortcutText.format(shortcut) {
                try container.encode(text)
            } else {
                try container.encode(
                    ShortcutObject(
                        keyCode: shortcut.keyCode, modifiers: ShortcutText.modifierNames(shortcut.modifiers),
                        label: shortcut.keyLabel))
            }
        }
    }
}

struct ConfigError: Error, LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Converts shortcuts to and from text such as "cmd+shift+]".
package enum ShortcutText {
    /// Modifier names in display order. The first name is the one written to the file.
    private static let modifiers: [([String], UInt64)] = [
        (["ctrl", "control", "⌃"], CGEventFlags.maskControl.rawValue),
        (["opt", "option", "alt", "⌥"], CGEventFlags.maskAlternate.rawValue),
        (["shift", "⇧"], CGEventFlags.maskShift.rawValue),
        (["cmd", "command", "⌘"], CGEventFlags.maskCommand.rawValue),
        (["fn"], CGEventFlags.maskSecondaryFn.rawValue),
    ]
    private static let modifiersByName = Dictionary(
        uniqueKeysWithValues: modifiers.flatMap { names, flag in names.map { ($0, flag) } })
    /// US-layout key names. When a key has several names, the first is the one written to the file.
    private static let keys: [(String, UInt16)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
        ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
        ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28),
        ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("return", 36),
        ("enter", 36), ("l", 37), ("j", 38), ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43),
        ("/", 44), ("n", 45), ("m", 46), (".", 47), ("tab", 48), ("space", 49), ("`", 50),
        ("delete", 51), ("backspace", 51), ("escape", 53), ("esc", 53), ("forwarddelete", 117),
        ("left", 123), ("right", 124), ("down", 125), ("up", 126), ("home", 115), ("end", 119),
        ("pageup", 116), ("pagedown", 121), ("f1", 122), ("f2", 120), ("f3", 99), ("f4", 118), ("f5", 96),
        ("f6", 97), ("f7", 98), ("f8", 100), ("f9", 101), ("f10", 109), ("f11", 103), ("f12", 111),
        ("f13", 105), ("f14", 107), ("f15", 113), ("f16", 106), ("f17", 64), ("f18", 79), ("f19", 80),
        ("f20", 90),
    ]
    private static let codesByName = Dictionary(
        keys.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })
    private static let namesByCode = Dictionary(
        keys.map { ($0.1, $0.0) }, uniquingKeysWith: { first, _ in first })

    package static func modifier(_ name: String) -> UInt64? { modifiersByName[name.lowercased()] }

    package static func modifierNames(_ flags: UInt64) -> [String] {
        modifiers.filter { flags & $0.1 != 0 }.map { $0.0[0] }
    }

    package static func name(for keyCode: UInt16) -> String? { namesByCode[keyCode] }

    package static func parse(_ text: String) throws -> Shortcut {
        var remaining = text.replacingOccurrences(of: " ", with: "")
        var modifiers: UInt64 = 0
        // Symbol modifiers can be written without "+", as in "⌘⇧T".
        while let first = remaining.first, let flag = modifiersByName[String(first)] {
            modifiers |= flag
            remaining.removeFirst()
        }
        var parts = remaining.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        guard let keyName = parts.popLast(), !keyName.isEmpty else {
            throw ConfigError(message: "\"\(text)\" has no key. Use a shortcut like \"cmd+shift+t\".")
        }
        for part in parts {
            guard let flag = modifier(part) else {
                throw ConfigError(message: "Unknown modifier \"\(part)\" in \"\(text)\"")
            }
            modifiers |= flag
        }
        guard let keyCode = codesByName[keyName.lowercased()] else {
            throw ConfigError(
                message:
                    "Unknown key \"\(keyName)\" in \"\(text)\". Use a letter, digit, punctuation, or a name like return, space, left, f5."
            )
        }
        let character = keyName.count == 1 ? keyName : nil
        return Shortcut(
            keyCode: keyCode, modifiers: modifiers, keyLabel: Shortcut.keyName(keyCode, characters: character)
        )
    }

    /// Returns nil when the text form would lose the shortcut's label, e.g. on a non-US layout.
    package static func format(_ shortcut: Shortcut) -> String? {
        guard let name = namesByCode[shortcut.keyCode] else { return nil }
        let character = name.count == 1 ? name : nil
        guard Shortcut.keyName(shortcut.keyCode, characters: character) == shortcut.keyLabel else {
            return nil
        }
        let known = modifiers.reduce(UInt64(0)) { $0 | $1.1 }
        guard shortcut.modifiers & ~known == 0 else { return nil }
        return (modifierNames(shortcut.modifiers) + [name]).joined(separator: "+")
    }
}

package enum ConfigJSON {
    package static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mx-forward/config.json")

    static func document(from preferences: Preferences) -> ConfigDocument {
        var buttons = ConfigDocument.Buttons()
        for (_, control) in ConfigDocument.Buttons.names {
            let mapping = preferences.buttons[control]
            func action(_ slot: ButtonSlot) -> ConfigAction { .action(mapping[slot]) }
            buttons[control] = .init(
                enabled: mapping.enabled, click: action(.click), hold: action(.hold), up: action(.up),
                down: action(.down), left: action(.left), right: action(.right),
                holdDelayMs: mapping.holdMilliseconds,
                dragSensitivityPercent: percent(mapping.dragSensitivity),
                zoomSpeedPercent: percent(mapping.zoomSpeed))
        }
        return ConfigDocument(
            testMode: preferences.testMode, buttons: buttons,
            wheel: .init(
                enabled: preferences.wheelEnabled, speedPercent: percent(preferences.wheelSpeed),
                accelerationPercent: percent(preferences.wheelAcceleration),
                natural: preferences.wheelNatural,
                mode: preferences.wheelMode),
            thumbWheel: .init(
                direction: preferences.horizontalDirection, speedPercent: percent(preferences.horizontalSpeed)
            ))
    }

    package static func encode(_ preferences: Preferences) -> String {
        guard let data = try? JSONEncoder().encode(document(from: preferences)),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return "{}\n" }
        return write(object, indent: "") + "\n"
    }

    private static let keyOrder =
        ["testMode", "buttons"] + ConfigDocument.Buttons.names.map(\.0) + [
            "wheel", "thumbWheel", "enabled", "click", "hold", "up", "down", "left", "right", "holdDelayMs",
            "dragSensitivityPercent", "zoomSpeedPercent", "speedPercent", "accelerationPercent", "natural",
            "mode",
            "direction", "keyCode", "modifiers", "label",
        ]

    /// Pretty-prints with keys in `keyOrder`, since JSONEncoder's key order isn't stable.
    private static func write(_ value: Any, indent: String) -> String {
        let inner = indent + "  "
        switch value {
        case let object as [String: Any]:
            let keys = object.keys.sorted {
                (keyOrder.firstIndex(of: $0) ?? .max, $0) < (keyOrder.firstIndex(of: $1) ?? .max, $1)
            }
            let fields = keys.map {
                "\(inner)\(write($0, indent: inner)): \(write(object[$0]!, indent: inner))"
            }
            return fields.isEmpty ? "{}" : "{\n" + fields.joined(separator: ",\n") + "\n\(indent)}"
        case let array as [Any]:
            return "[" + array.map { write($0, indent: inner) }.joined(separator: ", ") + "]"
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return number.boolValue ? "true" : "false"
        case let number as NSNumber:
            let double = number.doubleValue
            return double == double.rounded() && abs(double) < 1e15 ? String(Int64(double)) : "\(double)"
        default:
            let data = try? JSONSerialization.data(
                withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            return data.map { String(decoding: $0, as: UTF8.self) } ?? "null"
        }
    }

    /// Returns `base` with every setting listed in `text` replaced.
    package static func apply(_ text: String, to base: Preferences) throws -> Preferences {
        let document: ConfigDocument
        do { document = try JSONDecoder().decode(ConfigDocument.self, from: Data(text.utf8)) } catch {
            throw ConfigError(message: describe(error))
        }
        var result = base
        if let testMode = document.testMode { result.testMode = testMode }
        for (name, control) in ConfigDocument.Buttons.names {
            guard let button = document.buttons?[control] else { continue }
            let current = base.buttons[control]
            var mapping = current
            if let enabled = button.enabled { mapping.enabled = enabled }
            for slot in ButtonSlot.allCases {
                guard let value = button[slot] else { continue }
                let action: ButtonAction
                switch value {
                case .default: action = ButtonMapping.defaults(for: control)[slot]
                case .action(let chosen): action = chosen
                }
                guard ButtonAction.Kind.choices(for: slot).contains(action.kind) else {
                    throw ConfigError(
                        message:
                            "buttons.\(name).\(slot.rawValue): \"\(action.kind.rawValue)\" is not available for this slot."
                    )
                }
                mapping[slot] = action
            }
            if mapping.dragScroll && !ButtonSlot.directions.allSatisfy({ mapping[$0].kind == .scroll }) {
                throw ConfigError(
                    message:
                        "buttons.\(name): scroll uses all four directions, so set up, down, left, and right to \"scroll\"."
                )
            }
            guard (mapping.up.kind == .zoom) == (mapping.down.kind == .zoom) else {
                throw ConfigError(
                    message: "buttons.\(name): zoom uses both up and down, so set both to \"zoom\".")
            }
            if let delay = button.holdDelayMs { mapping.holdMilliseconds = delay }
            if let sensitivity = button.dragSensitivityPercent {
                mapping.dragSensitivity = scaled(sensitivity, keeping: current.dragSensitivity)
            }
            if let speed = button.zoomSpeedPercent {
                mapping.zoomSpeed = scaled(speed, keeping: current.zoomSpeed)
            }
            result.buttons[control] = mapping
        }
        if let wheel = document.wheel {
            if let enabled = wheel.enabled { result.wheelEnabled = enabled }
            if let speed = wheel.speedPercent { result.wheelSpeed = scaled(speed, keeping: base.wheelSpeed) }
            if let acceleration = wheel.accelerationPercent {
                result.wheelAcceleration = scaled(acceleration, keeping: base.wheelAcceleration)
            }
            if let natural = wheel.natural { result.wheelNatural = natural }
            if let mode = wheel.mode { result.wheelMode = mode }
        }
        if let direction = document.thumbWheel?.direction { result.horizontalDirection = direction }
        if let speed = document.thumbWheel?.speedPercent {
            result.horizontalSpeed = scaled(speed, keeping: base.horizontalSpeed)
        }
        return result.normalized()
    }

    private static func percent(_ value: Double) -> Double { (value * 100).rounded() }

    /// Keeps the exact stored value when its rounded percentage is unchanged.
    private static func scaled(_ percent: Double, keeping current: Double) -> Double {
        percent == Self.percent(current) ? current : percent / 100
    }

    package static func describe(_ error: Error) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
            return keys.isEmpty ? "" : keys.joined(separator: ".") + ": "
        }
        guard let error = error as? DecodingError else { return error.localizedDescription }
        switch error {
        case .dataCorrupted(let context):
            if let underlying = context.underlyingError as NSError?,
                let detail = underlying.userInfo[NSDebugDescriptionErrorKey] as? String
            {
                return "Invalid JSON: \(detail)"
            }
            return path(context) + context.debugDescription
        case .typeMismatch(let type, let context), .valueNotFound(let type, let context):
            return path(context) + "expected \(typeName(type))"
        default:
            return error.localizedDescription
        }
    }

    private static func typeName(_ type: Any.Type) -> String {
        switch type {
        case is Bool.Type: return "true or false"
        case is Double.Type, is Int.Type: return "a number"
        case is String.Type: return "a string"
        default: return "a valid value"
        }
    }
}
