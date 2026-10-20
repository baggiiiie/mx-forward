import AppKit
import ForwardCore

package enum ActionOutput {
    private static let source = CGEventSource(stateID: .privateState)

    /// The keys an action presses, or nil when it doesn't press any.
    package static func shortcut(for action: ButtonAction) -> Shortcut? {
        action.kind == .shortcut ? action.shortcut : WindowNavigationOutput.currentShortcut(action.kind)
    }

    /// Returns false when macOS refused the event.
    package static func send(_ action: ButtonAction, at point: CGPoint) -> Bool {
        switch action.kind {
        case .none, .zoom, .scroll: return true
        case .smartZoom: return ZoomOutput.send(.click, at: point)
        case .middleClick: return click(button: .center)
        case .modifierClick:
            guard let modifiers = action.modifiers, modifiers & KeyboardModifiers.mask.rawValue != 0 else {
                return true
            }
            return click(button: .left, modifiers: modifiers)
        case .shortcut, .missionControl, .appExpose, .desktopLeft, .desktopRight:
            return shortcut(for: action).map(KeyboardOutput.send) ?? true
        }
    }

    private static func click(button: CGMouseButton, modifiers: UInt64 = 0) -> Bool {
        guard AXIsProcessTrusted(), let location = CGEvent(source: nil)?.location,
            let (down, up) = clickEvents(button: button, modifiers: modifiers, at: location)
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    package static func clickEvents(
        button: CGMouseButton, modifiers: UInt64 = 0, at point: CGPoint
    ) -> (CGEvent, CGEvent)? {
        let types: (CGEventType, CGEventType)
        switch button {
        case .left: types = (.leftMouseDown, .leftMouseUp)
        case .right: types = (.rightMouseDown, .rightMouseUp)
        default: types = (.otherMouseDown, .otherMouseUp)
        }
        guard let source,
            let down = CGEvent(
                mouseEventSource: source, mouseType: types.0, mouseCursorPosition: point, mouseButton: button),
            let up = CGEvent(
                mouseEventSource: source, mouseType: types.1, mouseCursorPosition: point, mouseButton: button)
        else { return nil }
        let flags = CGEventSource.flagsState(.combinedSessionState)
            .union(CGEventFlags(rawValue: modifiers).intersection(KeyboardModifiers.mask))
        for event in [down, up] {
            event.flags = flags
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        return (down, up)
    }
}

package enum ZoomOutput {
    package static func send(_ action: ZoomAction, at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(), let event = ZoomEvent.make(action, at: point) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
