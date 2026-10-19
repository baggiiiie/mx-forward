import AppKit
import CoreGraphics
import ForwardCore

package enum KeyboardModifiers {
    package static let mask: CGEventFlags = [
        .maskControl, .maskAlternate, .maskShift, .maskCommand, .maskSecondaryFn,
    ]

    package static func label(_ modifiers: UInt64) -> String {
        let flags = CGEventFlags(rawValue: modifiers)
        return [
            (CGEventFlags.maskControl, "⌃"), (.maskAlternate, "⌥"),
            (.maskShift, "⇧"), (.maskCommand, "⌘"), (.maskSecondaryFn, "fn "),
        ].filter { flags.contains($0.0) }.map(\.1).joined()
    }
}

package struct Shortcut: Codable, Equatable {
    package var keyCode: UInt16
    package var modifiers: UInt64
    package var keyLabel: String

    package init(keyCode: UInt16, modifiers: UInt64, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
    package static let forward = Shortcut(
        keyCode: 30, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "]")
    package static let back = Shortcut(
        keyCode: 33, modifiers: CGEventFlags.maskCommand.rawValue, keyLabel: "[")

    package var label: String { KeyboardModifiers.label(modifiers) + keyLabel }

    package static func recorded(from event: NSEvent) -> Shortcut {
        var flags = CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)).intersection(
            KeyboardModifiers.mask)
        if (123...126).contains(event.keyCode) { flags.remove(.maskSecondaryFn) }
        return Shortcut(
            keyCode: event.keyCode, modifiers: UInt64(flags.rawValue),
            keyLabel: keyName(event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    package static func keyName(_ keyCode: UInt16, characters: String? = nil) -> String {
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

package struct ButtonAction: Codable, Equatable {
    package enum Kind: String, Codable, CaseIterable, Identifiable {
        case none, shortcut, modifierClick, missionControl, appExpose, desktopLeft, desktopRight, smartZoom,
            middleClick
        case zoom, scroll
        package var id: Self { self }
        package var label: String {
            switch self {
            case .none: return "No action"
            case .shortcut: return "Keyboard shortcut"
            case .modifierClick: return "Click with modifier"
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
        package static func choices(for slot: ButtonSlot) -> [Kind] {
            switch slot {
            case .click, .hold: return allCases.filter { $0 != .zoom && $0 != .scroll }
            case .left, .right: return allCases.filter { $0 != .zoom }
            case .up, .down: return allCases
            }
        }
    }

    package var kind: Kind
    package var shortcut: Shortcut?
    package var modifiers: UInt64?

    package init(_ kind: Kind, shortcut: Shortcut? = nil, modifiers: UInt64? = nil) {
        self.kind = kind
        self.shortcut = kind == .shortcut ? shortcut : nil
        let flags = (modifiers ?? 0) & KeyboardModifiers.mask.rawValue
        self.modifiers = kind == .modifierClick && flags != 0 ? flags : nil
    }

    package static func shortcut(_ shortcut: Shortcut?) -> ButtonAction {
        ButtonAction(.shortcut, shortcut: shortcut)
    }

    package var isNone: Bool { kind == .none }
    package var label: String {
        switch kind {
        case .shortcut: return shortcut?.label ?? "Shortcut not set"
        case .modifierClick:
            return modifiers.map {
                KeyboardModifiers.label($0).trimmingCharacters(in: .whitespaces) + " click"
            } ?? "Modifiers not set"
        default: return kind.label
        }
    }
}

/// What one button does on click, hold, and drag, plus its timing.
package struct ButtonMapping: Codable, Equatable {
    package init() {}
    package var enabled = true
    package var click = ButtonAction(.none)
    package var hold = ButtonAction(.none)
    package var up = ButtonAction(.none)
    package var down = ButtonAction(.none)
    package var left = ButtonAction(.none)
    package var right = ButtonAction(.none)
    package var holdMilliseconds = 400.0
    package var dragSensitivity = 1.0
    package var zoomSpeed = 2.0

    package subscript(_ slot: ButtonSlot) -> ButtonAction {
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
    package mutating func set(_ action: ButtonAction, for slot: ButtonSlot) {
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

    package var dragScroll: Bool { ButtonSlot.directions.contains { self[$0].kind == .scroll } }
    package var verticalZoom: Bool { up.kind == .zoom || down.kind == .zoom }
    package var reportsMovement: Bool { ButtonSlot.directions.contains { !self[$0].isNone } }

    package func normalized() -> ButtonMapping {
        var value = self
        for slot in ButtonSlot.allCases {
            let action = value[slot]
            value[slot] =
                ButtonAction.Kind.choices(for: slot).contains(action.kind)
                ? ButtonAction(action.kind, shortcut: action.shortcut, modifiers: action.modifiers)
                : ButtonAction(.none)
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

    package static func defaults(for control: MouseControl) -> ButtonMapping {
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

package struct ButtonMappings: Codable, Equatable {
    package init() {}
    package var forward = ButtonMapping.defaults(for: .forward)
    package var back = ButtonMapping.defaults(for: .back)
    package var thumb = ButtonMapping.defaults(for: .thumb)
    package var top = ButtonMapping.defaults(for: .top)
    package var middle = ButtonMapping.defaults(for: .middle)

    package subscript(_ control: MouseControl) -> ButtonMapping {
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

package struct MouseConfiguration: Equatable {
    package var controls: Set<MouseControl>
    package var movementControls: Set<MouseControl>
    package var wheelMode: WheelMode?
    package var horizontalInverted: Bool?
    package var horizontalDiverted = false
}

package enum WheelMode: String, Codable, CaseIterable, Identifiable {
    case unchanged, ratchet, freeSpin
    package var id: Self { self }
    package var label: String {
        switch self {
        case .unchanged: return "Keep current mode"
        case .ratchet: return "Ratchet"
        case .freeSpin: return "Free-spin"
        }
    }
}

package enum HorizontalDirection: String, Codable, CaseIterable, Identifiable {
    case unchanged, standard, reversed
    package var id: Self { self }
    package var label: String {
        switch self {
        case .unchanged: return "Keep current direction"
        case .standard: return "Standard"
        case .reversed: return "Reversed"
        }
    }
    package var inverted: Bool? {
        switch self {
        case .unchanged: return nil
        case .standard: return false
        case .reversed: return true
        }
    }
}

package struct Preferences: Codable, Equatable {
    package var testMode = true
    package var resumeMappings = false
    package var buttons = ButtonMappings()
    package var wheelEnabled = false
    package var wheelSpeed = 1.0
    package var wheelAcceleration = 1.0
    package var wheelNatural = true
    package var wheelMode = WheelMode.unchanged
    package var horizontalDirection = HorizontalDirection.unchanged
    package var horizontalSpeed = 1.0

    package var hasMappings: Bool {
        !controls.isEmpty || wheelEnabled || horizontalDirection.inverted != nil || horizontalSpeed != 1
    }

    package var controls: Set<MouseControl> { Set(MouseControl.allCases.filter { buttons[$0].enabled }) }

    package var hardwareConfiguration: MouseConfiguration {
        MouseConfiguration(
            controls: controls, movementControls: controls.filter { buttons[$0].reportsMovement },
            wheelMode: wheelEnabled ? wheelMode : nil, horizontalInverted: horizontalDirection.inverted,
            horizontalDiverted: horizontalSpeed != 1)
    }

    package init() {}

    private enum CodingKeys: String, CodingKey {
        case testMode, resumeMappings, buttons
        case wheelEnabled, wheelSpeed, wheelAcceleration, wheelNatural, wheelMode, horizontalDirection
        case horizontalSpeed
    }

    package init(from decoder: Decoder) throws {
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
        horizontalSpeed = try values.decodeIfPresent(Double.self, forKey: .horizontalSpeed) ?? 1
    }

    package static let storageKey = "preferences.v1"
    package static func load(defaults: UserDefaults = .standard) -> Preferences {
        guard let data = defaults.data(forKey: storageKey),
            let value = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return value.normalized()
    }
    package func normalized() -> Preferences {
        var value = self
        for control in MouseControl.allCases { value.buttons[control] = value.buttons[control].normalized() }
        value.wheelSpeed = clamp(value.wheelSpeed, 0.25...6, fallback: 1)
        value.wheelAcceleration = clamp(value.wheelAcceleration, 0...2, fallback: 1)
        value.horizontalSpeed = clamp(value.horizontalSpeed, 0.25...6, fallback: 1)
        return value
    }
    package func save(defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
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

package func clamp(_ value: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
    value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
}

package enum KeyboardOutput {
    package static func send(_ shortcut: Shortcut) -> Bool {
        guard AXIsProcessTrusted(), let (down, up) = events(for: shortcut) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    package static func events(for shortcut: Shortcut) -> (CGEvent, CGEvent)? {
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
