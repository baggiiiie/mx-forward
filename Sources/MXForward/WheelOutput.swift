import AppKit

enum WheelOutput {
    static func event(pixels: Int32) -> CGEvent? {
        guard let source = CGEventSource(stateID: .privateState),
            let event = CGEvent(
                scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1,
                wheel1: pixels, wheel2: 0, wheel3: 0)
        else { return nil }
        event.flags = CGEventSource.flagsState(.combinedSessionState)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.location = CGEvent(source: nil)?.location ?? .zero
        return event
    }

    static func send(pixels: Int32) -> Bool {
        guard pixels != 0 else { return true }
        guard AXIsProcessTrusted(), let event = event(pixels: pixels) else { return false }
        event.post(tap: .cghidEventTap)
        return true
    }
}
