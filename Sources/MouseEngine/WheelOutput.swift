import AppKit
import ForwardCore

package enum WheelOutput {
    package static func event(
        pixels: Int32, horizontal: Int32 = 0, phase: CGScrollPhase? = nil,
        at point: CGPoint? = nil
    ) -> CGEvent? {
        guard let source = CGEventSource(stateID: .privateState),
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel,
                wheelCount: horizontal == 0 && phase == nil ? 1 : 2,
                wheel1: pixels, wheel2: horizontal, wheel3: 0)
        else { return nil }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = point ?? CGEvent(source: nil)?.location ?? .zero
        if let phase {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        }
        return event
    }

    package static func dragEvent(_ action: DragScrollAction, at point: CGPoint) -> CGEvent? {
        let x: Int32
        let y: Int32
        let phase: CGScrollPhase
        switch action {
        case .begin: (x, y, phase) = (0, 0, .began)
        case .move(let dx, let dy): (x, y, phase) = (dx, dy, .changed)
        case .end: (x, y, phase) = (0, 0, .ended)
        case .cancel: (x, y, phase) = (0, 0, .cancelled)
        }
        return event(pixels: y, horizontal: x, phase: phase, at: point)
    }

    package static func send(pixels: Int32) -> Bool {
        guard pixels != 0 else { return true }
        guard AXIsProcessTrusted(), let event = event(pixels: pixels) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
