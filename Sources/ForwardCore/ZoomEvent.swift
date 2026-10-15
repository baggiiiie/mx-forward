import CoreGraphics

/// macOS gesture fields are undocumented; keep them in one adapter.
public enum ZoomEvent {
    public static func make(_ action: ZoomAction, at point: CGPoint) -> CGEvent? {
        guard let source = CGEventSource(stateID: .privateState),
            let event = CGEvent(source: source)
        else { return nil }
        event.type = CGEventType(rawValue: 29)!
        event.location = point
        event.flags = []

        let subtype = CGEventField(rawValue: 110)!
        let phase = CGEventField(rawValue: 132)!
        event.setIntegerValueField(subtype, value: action == .click ? 22 : 8)
        switch action {
        case .click: break
        case .begin: event.setIntegerValueField(phase, value: 1)
        case .magnify(let amount):
            event.setIntegerValueField(phase, value: 2)
            event.setDoubleValueField(CGEventField(rawValue: 113)!, value: amount)
        case .end: event.setIntegerValueField(phase, value: 4)
        case .cancel: event.setIntegerValueField(phase, value: 8)
        }
        return event
    }
}
