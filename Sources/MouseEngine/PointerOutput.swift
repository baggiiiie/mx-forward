import AppKit

/// Replays pointer movement while the mouse sends raw drag reports.
@MainActor
package struct PointerOutput {
    package private(set) var location: CGPoint
    private let displays: [CGRect]

    package init(at location: CGPoint, displays: [CGRect]? = nil) {
        self.location = location
        self.displays =
            displays
            ?? NSScreen.screens.compactMap { screen in
                guard
                    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                        as? NSNumber
                else { return nil }
                return CGDisplayBounds(number.uint32Value)
            }
    }

    package mutating func event(dx: Int16, dy: Int16) -> CGEvent? {
        let proposed = CGPoint(x: location.x + Double(dx), y: location.y + Double(dy))
        let target =
            displays.map { bounds in
                CGPoint(
                    x: min(max(proposed.x, bounds.minX), bounds.maxX - 1),
                    y: min(max(proposed.y, bounds.minY), bounds.maxY - 1))
            }.min { a, b in
                hypot(a.x - proposed.x, a.y - proposed.y) < hypot(b.x - proposed.x, b.y - proposed.y)
            } ?? proposed
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left
            )
        else { return nil }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(target.x - location.x))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(target.y - location.y))
        // Keep our own position: posted events may not have reached macOS yet.
        location = target
        return event
    }

    package mutating func send(dx: Int16, dy: Int16) -> Bool {
        guard AXIsProcessTrusted(), let event = event(dx: dx, dy: dy) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
