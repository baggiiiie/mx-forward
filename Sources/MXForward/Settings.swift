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

struct ButtonAction: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case none, shortcut, missionControl, appExpose, desktopLeft, desktopRight, smartZoom, middleClick
        case zoom, scroll
        var id: Self { self }
        var label: String {
            switch self {
            case .none: return "No action"
            case .shortcut: return "Keyboard shortcut"
            case .missionControl: return "Mission Control"
            case .appExpose: return "App Exposé"
            case .desktopLeft: return "Desktop left"
            case .desktopRight: return "Desktop right"
            case .smartZoom: return "Smart Zoom"
            case .middleClick: return "Middle click"
            case .zoom: return "Zoom"
            case .scroll: return "Scroll & navigate"
            }
        }
        static func choices(for slot: ButtonSlot) -> [Kind] {
            switch slot {
            case .click, .hold: return allCases.filter { $0 != .zoom && $0 != .scroll }
            case .left, .right: return allCases.filter { $0 != .zoom }
            case .up, .down: return allCases
            }
        }
    }

    var kind: Kind
    var shortcut: Shortcut?

    init(_ kind: Kind, shortcut: Shortcut? = nil) {
        self.kind = kind
        self.shortcut = kind == .shortcut ? shortcut : nil
    }

    static func shortcut(_ shortcut: Shortcut?) -> ButtonAction {
        ButtonAction(.shortcut, shortcut: shortcut)
    }

    var isNone: Bool { kind == .none }
    var label: String { kind == .shortcut ? shortcut?.label ?? "Shortcut not set" : kind.label }
}

/// What one button does on click, hold, and drag, plus its timing.
struct ButtonMapping: Codable, Equatable {
    var enabled = true
    var click = ButtonAction(.none)
    var hold = ButtonAction(.none)
    var up = ButtonAction(.none)
    var down = ButtonAction(.none)
    var left = ButtonAction(.none)
    var right = ButtonAction(.none)
    var holdMilliseconds = 400.0
    var dragSensitivity = 1.0
    var zoomSpeed = 2.0

    subscript(_ slot: ButtonSlot) -> ButtonAction {
        get {
            switch slot {
            case .click: return click
            case .hold: return hold
            case .up: return up
            case .down: return down
            case .left: return left
            case .right: return right
            }
        }
        set {
            switch slot {
            case .click: click = newValue
            case .hold: hold = newValue
            case .up: up = newValue
            case .down: down = newValue
            case .left: left = newValue
            case .right: right = newValue
            }
        }
    }

    /// Zoom links up and down; scrolling links all four directions.
    mutating func set(_ action: ButtonAction, for slot: ButtonSlot) {
        let wasZoom = verticalZoom
        if ButtonSlot.directions.contains(slot) {
            if action.kind == .scroll {
                for direction in ButtonSlot.directions { self[direction] = action }
                return
            }
            if dragScroll {
                for direction in ButtonSlot.directions { self[direction] = ButtonAction(.none) }
            }
        }
        self[slot] = action
        guard slot == .up || slot == .down else { return }
        let other: ButtonSlot = slot == .up ? .down : .up
        if action.kind == .zoom {
            self[other] = action
        } else if wasZoom {
            self[other] = ButtonAction(.none)
        }
    }

    var dragScroll: Bool { ButtonSlot.directions.contains { self[$0].kind == .scroll } }
    var verticalZoom: Bool { up.kind == .zoom || down.kind == .zoom }
    var reportsMovement: Bool { ButtonSlot.directions.contains { !self[$0].isNone } }

    func normalized() -> ButtonMapping {
        var value = self
        for slot in ButtonSlot.allCases where !ButtonAction.Kind.choices(for: slot).contains(value[slot].kind)
        {
            value[slot] = ButtonAction(.none)
        }
        if value.dragScroll {
            for slot in ButtonSlot.directions { value[slot] = ButtonAction(.scroll) }
        }
        if value.verticalZoom {
            value.up = ButtonAction(.zoom)
            value.down = ButtonAction(.zoom)
        }
        value.holdMilliseconds = clamp(value.holdMilliseconds, 150...1500, fallback: 400)
        value.dragSensitivity = clamp(value.dragSensitivity, 0.25...3, fallback: 1)
        value.zoomSpeed = clamp(value.zoomSpeed, 0.25...6, fallback: 2)
        return value
    }

    static func defaults(for control: MouseControl) -> ButtonMapping {
        var mapping = ButtonMapping()
        switch control {
        case .forward: mapping.click = .shortcut(.forward)
        case .back: mapping.click = .shortcut(.back)
        case .thumb:
            mapping.click = ButtonAction(.missionControl)
            mapping.up = ButtonAction(.missionControl)
            mapping.down = ButtonAction(.appExpose)
            mapping.left = ButtonAction(.desktopLeft)
            mapping.right = ButtonAction(.desktopRight)
        case .top:
            mapping.click = ButtonAction(.smartZoom)
            mapping.up = ButtonAction(.zoom)
            mapping.down = ButtonAction(.zoom)
        case .middle:
            // Diverting the wheel button replaces the native middle click, so it starts off.
            mapping.enabled = false
            mapping.click = ButtonAction(.middleClick)
        }
        return mapping
    }
}

struct ButtonMappings: Codable, Equatable {
    var forward = ButtonMapping.defaults(for: .forward)
    var back = ButtonMapping.defaults(for: .back)
    var thumb = ButtonMapping.defaults(for: .thumb)
    var top = ButtonMapping.defaults(for: .top)
    var middle = ButtonMapping.defaults(for: .middle)

    subscript(_ control: MouseControl) -> ButtonMapping {
        get {
            switch control {
            case .forward: return forward
            case .back: return back
            case .thumb: return thumb
            case .top: return top
            case .middle: return middle
            }
        }
        set {
            switch control {
            case .forward: forward = newValue
            case .back: back = newValue
            case .thumb: thumb = newValue
            case .top: top = newValue
            case .middle: middle = newValue
            }
        }
    }
}

struct MouseConfiguration: Equatable {
    var controls: Set<MouseControl>
    var movementControls: Set<MouseControl>
    var wheelMode: WheelMode?
    var horizontalInverted: Bool?
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
    var testMode = true
    var resumeMappings = false
    var buttons = ButtonMappings()
    var wheelEnabled = false
    var wheelSpeed = 1.0
    var wheelAcceleration = 1.0
    var wheelNatural = true
    var wheelMode = WheelMode.unchanged
    var horizontalDirection = HorizontalDirection.unchanged

    var hasMappings: Bool { !controls.isEmpty || wheelEnabled || horizontalDirection.inverted != nil }

    var controls: Set<MouseControl> { Set(MouseControl.allCases.filter { buttons[$0].enabled }) }

    var hardwareConfiguration: MouseConfiguration {
        MouseConfiguration(
            controls: controls, movementControls: controls.filter { buttons[$0].reportsMovement },
            wheelMode: wheelEnabled ? wheelMode : nil, horizontalInverted: horizontalDirection.inverted)
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case testMode, resumeMappings, buttons
        case wheelEnabled, wheelSpeed, wheelAcceleration, wheelNatural, wheelMode, horizontalDirection
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        testMode = try values.decodeIfPresent(Bool.self, forKey: .testMode) ?? true
        resumeMappings = try values.decodeIfPresent(Bool.self, forKey: .resumeMappings) ?? false
        buttons =
            try values.decodeIfPresent(ButtonMappings.self, forKey: .buttons)
            ?? LegacyButtons.migrate(try decoder.container(keyedBy: LegacyButtons.Keys.self))
        wheelEnabled = try values.decodeIfPresent(Bool.self, forKey: .wheelEnabled) ?? false
        wheelSpeed = try values.decodeIfPresent(Double.self, forKey: .wheelSpeed) ?? 1
        wheelAcceleration = try values.decodeIfPresent(Double.self, forKey: .wheelAcceleration) ?? 1
        wheelNatural = try values.decodeIfPresent(Bool.self, forKey: .wheelNatural) ?? true
        wheelMode = try values.decodeIfPresent(WheelMode.self, forKey: .wheelMode) ?? .unchanged
        horizontalDirection =
            try values.decodeIfPresent(HorizontalDirection.self, forKey: .horizontalDirection) ?? .unchanged
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
        for control in MouseControl.allCases { value.buttons[control] = value.buttons[control].normalized() }
        value.wheelSpeed = clamp(value.wheelSpeed, 0.25...6, fallback: 1)
        value.wheelAcceleration = clamp(value.wheelAcceleration, 0...2, fallback: 1)
        return value
    }
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// Reads button settings saved before every button shared the same click, hold, and drag options.
private enum LegacyButtons {
    enum Keys: String, CodingKey {
        case holdMilliseconds, shortcut, forwardEnabled, forwardHoldEnabled, forwardClick
        case backEnabled, backClick, thumbGesturesEnabled, thumbSensitivity, thumbShortcuts
        case topZoomEnabled, topClickAction, topClickShortcut, zoomSensitivity
    }

    private struct Mapping: Decodable {
        var source: String
        var shortcut: Shortcut?
    }

    static func migrate(_ values: KeyedDecodingContainer<Keys>) -> ButtonMappings {
        func bool(_ key: Keys) -> Bool? { try? values.decodeIfPresent(Bool.self, forKey: key) }
        func double(_ key: Keys) -> Double? { try? values.decodeIfPresent(Double.self, forKey: key) }
        func action(_ mapping: Mapping?, otherwise fallback: ButtonAction) -> ButtonAction {
            switch mapping?.source {
            case "custom": return .shortcut(mapping?.shortcut)
            case "none": return ButtonAction(.none)
            default: return fallback
            }
        }
        var buttons = ButtonMappings()

        buttons.forward.enabled = bool(.forwardEnabled) ?? true
        buttons.forward.click = action(
            try? values.decodeIfPresent(Mapping.self, forKey: .forwardClick), otherwise: buttons.forward.click
        )
        let holdShortcut = try? values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        if bool(.forwardHoldEnabled) ?? (holdShortcut != nil), let holdShortcut {
            buttons.forward.hold = .shortcut(holdShortcut)
        }
        buttons.forward.holdMilliseconds = double(.holdMilliseconds) ?? 400

        buttons.back.enabled = bool(.backEnabled) ?? true
        buttons.back.click = action(
            try? values.decodeIfPresent(Mapping.self, forKey: .backClick), otherwise: buttons.back.click)

        buttons.thumb.enabled = bool(.thumbGesturesEnabled) ?? true
        buttons.thumb.dragSensitivity = double(.thumbSensitivity) ?? 1
        let gestures = (try? values.decodeIfPresent([String: Mapping].self, forKey: .thumbShortcuts)) ?? [:]
        for slot in [ButtonSlot.click, .up, .down, .left, .right] {
            buttons.thumb[slot] = action(gestures[slot.rawValue], otherwise: buttons.thumb[slot])
        }

        buttons.top.enabled = bool(.topZoomEnabled) ?? true
        buttons.top.zoomSpeed = double(.zoomSensitivity) ?? 2
        switch try? values.decodeIfPresent(String.self, forKey: .topClickAction) {
        case "shortcut":
            buttons.top.click = .shortcut(
                try? values.decodeIfPresent(Shortcut.self, forKey: .topClickShortcut))
        case "none": buttons.top.click = ButtonAction(.none)
        default: break
        }
        return buttons
    }
}

func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
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
