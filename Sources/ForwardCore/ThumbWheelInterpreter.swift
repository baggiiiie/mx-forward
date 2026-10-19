public struct ThumbWheelResolution {
    /// Native scroll steps per reported increment; right is positive.
    public let stepsPerDelta: Double

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 5 else { return nil }
        let native = UInt16(payload[0]) << 8 | UInt16(payload[1])
        let diverted = UInt16(payload[2]) << 8 | UInt16(payload[3])
        guard native > 0, diverted > 0 else { return nil }
        stepsPerDelta = Double(native) / Double(diverted) * (payload[4] & 1 == 0 ? -1 : 1)
    }
}

public struct ThumbWheelScroll {
    public let delta: Int16

    public init?(_ packet: HIDPacket) {
        guard packet.function == 0, packet.softwareID == 0, packet.payload.count >= 6 else { return nil }
        delta = Int16(bitPattern: UInt16(packet.payload[0]) << 8 | UInt16(packet.payload[1]))
    }
}

public struct ThumbWheelInterpreter {
    private var remainder = 0.0
    private var direction = 0
    public init() {}

    public mutating func pixels(delta: Int16, stepsPerDelta: Double, speed: Double, natural: Bool) -> Int32 {
        guard delta != 0 else { return 0 }
        let nextDirection = delta > 0 ? 1 : -1
        if direction != nextDirection { remainder = 0 }
        direction = nextDirection
        let amount = remainder + Double(delta) * stepsPerDelta * 40 * speed * (natural ? 1 : -1)
        let whole = amount.rounded(.towardZero)
        remainder = amount - whole
        return Int32(min(Double(Int32.max), max(Double(Int32.min), whole)))
    }

    public mutating func cancel() { self = ThumbWheelInterpreter() }
}
