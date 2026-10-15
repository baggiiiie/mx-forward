public struct ThumbWheelReporting: Equatable {
    private let reporting: UInt8
    private let options: UInt8

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        reporting = payload[0]
        options = payload[1]
    }

    public var inverted: Bool { options & 1 != 0 }
    public var bytes: [UInt8] { [reporting, options] }

    public func parameters(inverted: Bool) -> [UInt8] {
        [reporting, (options & ~1) | (inverted ? 1 : 0)]
    }
}
