public enum MouseControl: UInt16, CaseIterable, Comparable {
    case back = 83
    case forward = 86
    case thumb = 195
    case top = 196

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    public var name: String {
        switch self {
        case .back: return "Back"
        case .forward: return "Forward"
        case .thumb: return "Thumb button"
        case .top: return "Top button"
        }
    }
    public var query: [UInt8] { [UInt8(rawValue >> 8), UInt8(rawValue & 255)] }
    public var reportsMovement: Bool { self == .thumb || self == .top }
}
