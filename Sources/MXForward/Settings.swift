import AppKit
import CoreGraphics
import ForwardCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var keyLabel: String
    static let forward = Shortcut(keyCode: 30, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "]")
    static let back = Shortcut(keyCode: 33, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "[")

    var label: String {
        let flags = CGEventFlags(rawValue: modifiers)
        return [
            (CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"),
            (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "fn "),
        ]
        .filter { flags.contains($0.0) }.map(\.1).joined() + keyLabel
    }

    static func recorded(from event: NSEvent) -> Shortcut {
        let mask: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
        var flags = event.modifierFlags.intersection(mask)
        if (123...126).contains(event.keyCode) { flags.remove(.function) }
        return Shortcut(
            keyCode: event.keyCode, modifiers: UInt64(flags.rawValue),
            keyLabel: keyName(event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    static func keyName(_ keyCode: UInt16, characters: String? = nil) -> String {
        let names: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
            53: "Escape", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        return names[keyCode] ?? characters?.uppercased() ?? "Key \(keyCode)"
    }
}

struct ShortcutMapping: Codable, Equatable {
    enum Source: String, Codable { case defaultShortcut, custom, none }
    var source = Source.defaultShortcut
    var shortcut: Shortcut?

    func resolve(default defaultShortcut: Shortcut?) -> Shortcut? {
        switch source {
        case .defaultShortcut: return defaultShortcut
        case .custom: return shortcut
        case .none: return nil
        }
    }
}

struct MouseConfiguration: Equatable {
    var controls: Set<MouseControl>
    var wheelMode: WheelMode?
    var horizontalInverted: Bool?
}

enum TopClickAction: String, Codable, CaseIterable, Identifiable {
    case smartZoom, shortcut, none
    var id: Self { self }
    var label: String {
        switch self {
        case .smartZoom: return "Smart Zoom"
        case .shortcut: return "Keyboard shortcut"
        case .none: return "No action"
        }
    }
}

enum WheelMode: String, Codable, CaseIterable, Identifiable {
    case unchanged, ratchet, freeSpin
    var id: Self { self }
    var label: String {
        switch self {
        case .unchanged: return "Keep current mode"
        case .ratchet: return "Ratchet"
        case .freeSpin: return "Free-spin"
        }
    }
}

enum HorizontalDirection: String, Codable, CaseIterable, Identifiable {
    case unchanged, standard, reversed
    var id: Self { self }
    var label: String {
        switch self {
        case .unchanged: return "Keep current direction"
        case .standard: return "Standard"
        case .reversed: return "Reversed"
        }
    }
    var inverted: Bool? {
        switch self {
        case .unchanged: return nil
        case .standard: return false
        case .reversed: return true
        }
    }
}

struct Preferences: Codable, Equatable {
    var holdMilliseconds: Double = 400
    var shortcut: Shortcut?
    var testMode = true
    var resumeMappings = false
    var forwardEnabled = true
    var backEnabled = true
    var forwardHoldEnabled = false
    var topZoomEnabled = true
    var thumbGesturesEnabled = true
    var thumbSensitivity = 1.0
    var wheelEnabled = false
    var wheelSpeed = 1.0
    var wheelAcceleration = 1.0
    var wheelNatural = true
    var wheelMode = WheelMode.unchanged
    var horizontalDirection = HorizontalDirection.unchanged
    var zoomSensitivity = 2.0
    var topClickAction = TopClickAction.smartZoom
    var topClickShortcut: Shortcut?
    var forwardClick = ShortcutMapping()
    var backClick = ShortcutMapping()
    var thumbShortcuts: [String: ShortcutMapping] = [:]

    var hasMappings: Bool { !controls.isEmpty || wheelEnabled || horizontalDirection.inverted != nil }

    var hardwareConfiguration: MouseConfiguration {
        MouseConfiguration(
            controls: controls, wheelMode: wheelEnabled ? wheelMode : nil,
            horizontalInverted: horizontalDirection.inverted)
    }

    func thumbShortcut(_ action: ThumbGestureInterpreter.Action) -> Shortcut? {
        (thumbShortcuts[action.rawValue] ?? ShortcutMapping())
            .resolve(default: WindowNavigationOutput.currentShortcut(action))
    }

    var controls: Set<MouseControl> {
        var result = Set<MouseControl>()
        if forwardEnabled { result.insert(.forward) }
        if backEnabled { result.insert(.back) }
        if topZoomEnabled { result.insert(.top) }
        if thumbGesturesEnabled { result.insert(.thumb) }
        return result
    }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case holdMilliseconds, shortcut, testMode, forwardEnabled, topZoomEnabled, zoomSensitivity
        case topClickAction, topClickShortcut
        case backEnabled, forwardHoldEnabled
        case resumeMappings
        case thumbGesturesEnabled, thumbSensitivity
        case wheelEnabled, wheelSpeed, wheelNatural, wheelMode
        case wheelAcceleration
        case horizontalDirection
        case forwardClick, backClick, thumbShortcuts
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        holdMilliseconds = try values.decodeIfPresent(Double.self, forKey: .holdMilliseconds) ?? 400
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        testMode = try values.decodeIfPresent(Bool.self, forKey: .testMode) ?? true
        resumeMappings = try values.decodeIfPresent(Bool.self, forKey: .resumeMappings) ?? false
        forwardEnabled = try values.decodeIfPresent(Bool.self, forKey: .forwardEnabled) ?? true
        backEnabled = try values.decodeIfPresent(Bool.self, forKey: .backEnabled) ?? true
        forwardHoldEnabled =
            try values.decodeIfPresent(Bool.self, forKey: .forwardHoldEnabled) ?? (shortcut != nil)
        topZoomEnabled = try values.decodeIfPresent(Bool.self, forKey: .topZoomEnabled) ?? true
        thumbGesturesEnabled = try values.decodeIfPresent(Bool.self, forKey: .thumbGesturesEnabled) ?? true
        thumbSensitivity = try values.decodeIfPresent(Double.self, forKey: .thumbSensitivity) ?? 1
        wheelEnabled = try values.decodeIfPresent(Bool.self, forKey: .wheelEnabled) ?? false
        wheelSpeed = try values.decodeIfPresent(Double.self, forKey: .wheelSpeed) ?? 1
        wheelAcceleration = try values.decodeIfPresent(Double.self, forKey: .wheelAcceleration) ?? 1
        wheelNatural = try values.decodeIfPresent(Bool.self, forKey: .wheelNatural) ?? true
        wheelMode = try values.decodeIfPresent(WheelMode.self, forKey: .wheelMode) ?? .unchanged
        horizontalDirection =
            try values.decodeIfPresent(HorizontalDirection.self, forKey: .horizontalDirection) ?? .unchanged
        zoomSensitivity = try values.decodeIfPresent(Double.self, forKey: .zoomSensitivity) ?? 2
        topClickAction =
            try values.decodeIfPresent(TopClickAction.self, forKey: .topClickAction) ?? .smartZoom
        topClickShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .topClickShortcut)
        forwardClick =
            try values.decodeIfPresent(ShortcutMapping.self, forKey: .forwardClick) ?? ShortcutMapping()
        backClick = try values.decodeIfPresent(ShortcutMapping.self, forKey: .backClick) ?? ShortcutMapping()
        thumbShortcuts =
            try values.decodeIfPresent([String: ShortcutMapping].self, forKey: .thumbShortcuts) ?? [:]
    }
    static let storageKey = "preferences.v1"
    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
            let value = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return value.normalized()
    }
    func normalized() -> Preferences {
        var value = self
        if !value.holdMilliseconds.isFinite { value.holdMilliseconds = 400 }
        value.holdMilliseconds = min(1500, max(150, value.holdMilliseconds))
        if !value.zoomSensitivity.isFinite { value.zoomSensitivity = 2 }
        value.zoomSensitivity = min(6, max(0.25, value.zoomSensitivity))
        if !value.thumbSensitivity.isFinite { value.thumbSensitivity = 1 }
        value.thumbSensitivity = min(3, max(0.25, value.thumbSensitivity))
        if !value.wheelSpeed.isFinite { value.wheelSpeed = 1 }
        value.wheelSpeed = min(6, max(0.25, value.wheelSpeed))
        if !value.wheelAcceleration.isFinite { value.wheelAcceleration = 1 }
        value.wheelAcceleration = min(2, max(0, value.wheelAcceleration))
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

enum KeyboardOutput {
    static func send(_ shortcut: Shortcut) -> Bool {
        guard AXIsProcessTrusted(), let (down, up) = events(for: shortcut) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func events(for shortcut: Shortcut) -> (CGEvent, CGEvent)? {
        guard let source = CGEventSource(stateID: .privateState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        else { return nil }
        var flags = CGEventFlags(rawValue: shortcut.modifiers)
        // Arrow keys carry these flags on a physical keyboard too.
        if (123...126).contains(shortcut.keyCode) {
            flags.formUnion([.maskNumericPad, .maskSecondaryFn])
        }
        down.flags = flags
        up.flags = flags
        return (down, up)
    }
}
