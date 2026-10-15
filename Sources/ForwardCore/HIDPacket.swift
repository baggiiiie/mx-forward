public struct HIDPacket: Equatable {
    public let device: UInt8
    public let feature: UInt8
    public let address: UInt8
    public let payload: [UInt8]
    public var function: UInt8 { address >> 4 }
    public var softwareID: UInt8 { address & 15 }

    public static func parse(_ bytes: [UInt8]) -> HIDPacket? {
        guard let id = bytes.first, id == 0x10 || id == 0x11,
            bytes.count >= (id == 0x10 ? 7 : 20)
        else { return nil }
        return HIDPacket(
            device: bytes[1], feature: bytes[2], address: bytes[3],
            payload: Array(bytes[4..<(id == 0x10 ? 7 : 20)]))
    }

    public static func request(
        device: UInt8, feature: UInt8, function: UInt8,
        softwareID: UInt8, payload: [UInt8]
    ) -> [UInt8] {
        precondition(payload.count <= 16 && function < 16 && softwareID > 0 && softwareID < 16)
        var bytes = [UInt8](repeating: 0, count: payload.count > 3 ? 20 : 7)
        bytes[0] = bytes.count == 20 ? 0x11 : 0x10
        bytes[1] = device
        bytes[2] = feature
        bytes[3] = (function << 4) | softwareID
        bytes.replaceSubrange(4..<(4 + payload.count), with: payload)
        return bytes
    }

    public var error: (feature: UInt8, address: UInt8, code: UInt8)? {
        guard feature == 0xFF || feature == 0x8F, payload.count >= 2 else { return nil }
        return (address, payload[0], payload[1])
    }

    public var pressedControls: Set<UInt16> {
        var values = Set<UInt16>()
        for offset in stride(from: 0, to: payload.count - 1, by: 2) {
            let value = UInt16(payload[offset]) << 8 | UInt16(payload[offset + 1])
            if value != 0 { values.insert(value) }
        }
        return values
    }

    public var movement: (dx: Int16, dy: Int16)? {
        guard function == 1, softwareID == 0, payload.count >= 4 else { return nil }
        return (
            Int16(bitPattern: UInt16(payload[0]) << 8 | UInt16(payload[1])),
            Int16(bitPattern: UInt16(payload[2]) << 8 | UInt16(payload[3]))
        )
    }
}
