/// One button's current HID++ reporting settings.
public struct ControlReporting: Equatable {
    public let control: MouseControl
    public let remap: UInt16
    public let diverted: Bool
    public let persistent: Bool
    public let rawMovement: Bool

    public init?(_ payload: [UInt8], control: MouseControl) {
        guard payload.count >= 5, payload.starts(with: control.query) else { return nil }
        self.control = control
        remap = UInt16(payload[3]) << 8 | UInt16(payload[4])
        diverted = payload[2] & 0x01 != 0
        persistent = payload[2] & 0x04 != 0
        rawMovement = payload[2] & 0x10 != 0
    }

    public var temporarilyDiverted: Bool { diverted && !persistent }

    public func parameters(divert: Bool) -> [UInt8] {
        var flags: UInt8 = divert ? 0x0B : 0x0A
        // Gesture buttons need movement reports; release clears them.
        flags |= control.reportsMovement && divert ? 0x30 : 0x20
        return control.query + [flags, UInt8(remap >> 8), UInt8(remap & 255)]
    }
}
