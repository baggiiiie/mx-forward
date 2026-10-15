import AppKit
import CoreGraphics
import ForwardCore

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var keyLabel: String

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
        let names: [UInt16: String] = [
            36: "Return", 48: "Tab", 49: "Space", 51: "Delete",
            53: "Escape", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑",
            115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
            100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        let text = event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        return Shortcut(
            keyCode: event.keyCode,
            modifiers: UInt64(event.modifierFlags.intersection(mask).rawValue),
            keyLabel: names[event.keyCode] ?? text)
    }
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

struct Preferences: Codable {
    var holdMilliseconds: Double = 400
    var shortcut: Shortcut?
    var testMode = true
    var forwardEnabled = true
    var topZoomEnabled = true
    var zoomSensitivity = 2.0
    var topClickAction = TopClickAction.smartZoom
    var topClickShortcut: Shortcut?

    var shortcutsReady: Bool {
        (!forwardEnabled || shortcut != nil)
            && (!topZoomEnabled || topClickAction != .shortcut || topClickShortcut != nil)
    }

    var controls: Set<MouseControl> {
        var result = Set<MouseControl>()
        if forwardEnabled { result.insert(.forward) }
        if topZoomEnabled { result.insert(.top) }
        return result
    }

    init() {}
    private enum CodingKeys: String, CodingKey {
        case holdMilliseconds, shortcut, testMode, forwardEnabled, topZoomEnabled, zoomSensitivity
        case topClickAction, topClickShortcut
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        holdMilliseconds = try values.decodeIfPresent(Double.self, forKey: .holdMilliseconds) ?? 400
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        testMode = try values.decodeIfPresent(Bool.self, forKey: .testMode) ?? true
        forwardEnabled = try values.decodeIfPresent(Bool.self, forKey: .forwardEnabled) ?? true
        topZoomEnabled = try values.decodeIfPresent(Bool.self, forKey: .topZoomEnabled) ?? true
        zoomSensitivity = try values.decodeIfPresent(Double.self, forKey: .zoomSensitivity) ?? 2
        topClickAction =
            try values.decodeIfPresent(TopClickAction.self, forKey: .topClickAction) ?? .smartZoom
        topClickShortcut = try values.decodeIfPresent(Shortcut.self, forKey: .topClickShortcut)
    }
    static let storageKey = "preferences.v1"
    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
            var value = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        if !value.holdMilliseconds.isFinite { value.holdMilliseconds = 400 }
        value.holdMilliseconds = min(1500, max(150, value.holdMilliseconds))
        if !value.zoomSensitivity.isFinite { value.zoomSensitivity = 2 }
        value.zoomSensitivity = min(6, max(0.25, value.zoomSensitivity))
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

enum KeyboardOutput {
    static let forward = Shortcut(keyCode: 30, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "]")
    static func send(_ shortcut: Shortcut) -> Bool {
        guard AXIsProcessTrusted(),
            let source = CGEventSource(stateID: .privateState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        else { return false }
        down.flags = CGEventFlags(rawValue: shortcut.modifiers)
        up.flags = down.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
