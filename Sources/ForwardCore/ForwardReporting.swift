/// The Forward button's current HID++ reporting settings.
public struct ForwardReporting: Equatable {
    public static let controlID: UInt16 = 86
    public static let query: [UInt8] = [0, 86]

    public let remap: UInt16
    public let diverted: Bool
    public let persistent: Bool

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 5, payload.starts(with: Self.query) else { return nil }
        remap = UInt16(payload[3]) << 8 | UInt16(payload[4])
        diverted = payload[2] & 0x01 != 0
        persistent = payload[2] & 0x04 != 0
    }

    public var temporarilyDiverted: Bool { diverted && !persistent }

    public func parameters(divert: Bool) -> [UInt8] {
        // Change diversion flags, disable persistent diversion, and keep the remap target.
        Self.query + [divert ? 0x0B : 0x0A, UInt8(remap >> 8), UInt8(remap & 255)]
    }
}
