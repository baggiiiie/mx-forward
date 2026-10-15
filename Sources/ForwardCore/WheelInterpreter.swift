public struct WheelScroll: Equatable {
    public let delta: Int16
    public let highResolution: Bool

    public init?(_ packet: HIDPacket) {
        guard packet.function == 0, packet.softwareID == 0, packet.payload.count >= 3 else { return nil }
        highResolution = packet.payload[0] & 0x10 != 0
        delta = Int16(bitPattern: UInt16(packet.payload[1]) << 8 | UInt16(packet.payload[2]))
    }
}

public struct WheelInterpreter {
    private var remainder = 0.0
    public init() {}

    public mutating func pixels(
        for scroll: WheelScroll, multiplier: UInt8, speed: Double, natural: Bool
    ) -> Int32 {
        precondition(multiplier > 0 && speed.isFinite && speed > 0 && speed <= 6)
        let units = scroll.highResolution ? Double(multiplier) : 1
        let amount = remainder + Double(scroll.delta) / units * 40 * speed * (natural ? -1 : 1)
        let whole = Int32(amount.rounded(.towardZero))
        remainder = amount - Double(whole)
        return whole
    }

    public mutating func cancel() { remainder = 0 }
}
