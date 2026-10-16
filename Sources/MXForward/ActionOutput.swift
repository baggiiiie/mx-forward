import AppKit
import ForwardCore

enum ActionOutput {
    /// The keys an action presses, or nil when it doesn't press any.
    static func shortcut(for action: ButtonAction) -> Shortcut? {
        action.kind == .shortcut ? action.shortcut : WindowNavigationOutput.currentShortcut(action.kind)
    }

    /// Returns false when macOS refused the event.
    static func send(_ action: ButtonAction, at point: CGPoint) -> Bool {
        switch action.kind {
        case .none, .zoom: return true
        case .smartZoom: return ZoomOutput.send(.click, at: point)
        case .middleClick: return middleClick()
        case .shortcut, .missionControl, .appExpose, .desktopLeft, .desktopRight:
            return shortcut(for: action).map(KeyboardOutput.send) ?? true
        }
    }

    private static func middleClick() -> Bool {
        guard AXIsProcessTrusted(), let location = CGEvent(source: nil)?.location,
            let down = CGEvent(
                mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: location,
                mouseButton: .center),
            let up = CGEvent(
                mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: location,
                mouseButton: .center)
        else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}

enum ZoomOutput {
    static func send(_ action: ZoomAction, at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(), let event = ZoomEvent.make(action, at: point) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
