public struct ThumbWheelReporting: Equatable {
    public let diverted: Bool
    public let inverted: Bool

    public init?(_ payload: [UInt8]) {
        guard payload.count >= 2 else { return nil }
        diverted = payload[0] & 1 != 0
        inverted = payload[1] & 1 != 0
    }

    public var bytes: [UInt8] { parameters(inverted: inverted) }

    public func parameters(inverted: Bool, diverted: Bool? = nil) -> [UInt8] {
        [(diverted ?? self.diverted) ? 1 : 0, inverted ? 1 : 0]
    }
}
