public enum MouseControl: UInt16, CaseIterable, Comparable {
    case forward = 86
    case top = 196

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var name: String { self == .forward ? "Forward" : "Top button" }
    public var query: [UInt8] { [UInt8(rawValue >> 8), UInt8(rawValue & 255)] }
}
