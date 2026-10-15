import AppKit
import ForwardCore

enum ZoomOutput {
    static func send(_ action: ZoomAction, at point: CGPoint) -> Bool {
        guard AXIsProcessTrusted(), let event = ZoomEvent.make(action, at: point) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
