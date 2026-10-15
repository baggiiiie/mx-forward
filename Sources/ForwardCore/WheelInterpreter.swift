import Foundation

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
    private var lastTime: TimeInterval?
    private var direction = 0
    private var velocity = 0.0
    public init() {}

    public mutating func pixels(
        for scroll: WheelScroll, multiplier: UInt8, speed: Double, natural: Bool,
        acceleration: Double = 0, at time: TimeInterval
    ) -> Int32 {
        precondition(multiplier > 0 && speed.isFinite && speed > 0 && speed <= 6)
        precondition(acceleration.isFinite && (0...2).contains(acceleration))
        guard scroll.delta != 0 else { return 0 }
        let units = scroll.highResolution ? Double(multiplier) : 1
        let notches = Double(scroll.delta) / units
        let boost = gain(notches: notches, strength: acceleration, at: time)
        let amount = remainder + notches * 40 * speed * boost * (natural ? -1 : 1)
        let whole = Int32(amount.rounded(.towardZero))
        remainder = amount - Double(whole)
        return whole
    }

    private mutating func gain(notches: Double, strength: Double, at time: TimeInterval) -> Double {
        let previousTime = lastTime
        let previousDirection = direction
        lastTime = time.isFinite ? time : nil
        direction = notches > 0 ? 1 : -1
        if let previousTime, direction != previousDirection || time - previousTime >= 0.25 {
            remainder = 0
        }
        guard strength > 0, let previousTime, time.isFinite,
            time > previousTime, time - previousTime < 0.25, direction == previousDirection
        else {
            velocity = 0
            return 1
        }
        let elapsed = time - previousTime
        // Smooth notch speed over 80 ms so packet frequency does not set the acceleration.
        let weight = -expm1(-elapsed / 0.08)
        velocity = min(120, velocity * (1 - weight) + abs(notches) * (weight / elapsed))
        let ramp = min(1, max(0, (velocity - 10) / 50))
        return 1 + 4 * strength * ramp * ramp
    }

    public mutating func cancel() { self = WheelInterpreter() }
}
