import Foundation

public enum ButtonSlot: String, Codable, CaseIterable {
    case click, hold, up, down, left, right
    public static let directions: [ButtonSlot] = [.up, .down, .left, .right]
}

public enum ZoomAction: Equatable {
    case click
    case begin
    case magnify(Double)
    case end
    case cancel
}

/// Turns one button's press, movement, and release into a click, a hold, a drag direction,
/// or a continuous vertical zoom. Each press performs at most one of these.
public struct ButtonGesture {
    public struct Options: Equatable {
        /// Nil turns holds into clicks.
        public var holdDelay: TimeInterval?
        /// Movement in HID counts needed to pick a direction.
        public var dragDistance: Double
        /// Vertical movement zooms continuously instead of picking up or down.
        public var verticalZoom: Bool
        public var zoomSpeed: Double
        public var discardFirstReport: Bool

        public init(
            holdDelay: TimeInterval? = nil, dragDistance: Double = 120, verticalZoom: Bool = false,
            zoomSpeed: Double = 1, discardFirstReport: Bool = false
        ) {
            self.holdDelay = holdDelay
            self.dragDistance = dragDistance
            self.verticalZoom = verticalZoom
            self.zoomSpeed = zoomSpeed
            self.discardFirstReport = discardFirstReport
        }
    }

    public enum Event: Equatable {
        case action(ButtonSlot)
        case zoom(ZoomAction)
    }

    private enum State { case idle, pending, zooming, done }
    private static let zoomThreshold = 20.0

    private var state = State.idle
    private var options = Options()
    private var deadline: TimeInterval?
    private var discardFirst = false
    private var x = 0.0
    private var y = 0.0

    public init() {}

    public var isPressed: Bool { state != .idle }

    public mutating func down(at time: TimeInterval, options: Options) {
        guard state == .idle else { return }
        precondition(options.dragDistance.isFinite && options.dragDistance > 0)
        self = ButtonGesture()
        state = .pending
        self.options = options
        deadline = options.holdDelay.map { time + $0 }
        discardFirst = options.discardFirstReport
    }

    public mutating func move(dx: Int16, dy: Int16) -> [Event] {
        guard state == .pending || state == .zooming else { return [] }
        if discardFirst {
            discardFirst = false
            return []
        }
        if state == .zooming { return magnify(Double(dy)) }
        x += Double(dx)
        y += Double(dy)
        if options.verticalZoom && abs(y) >= Self.zoomThreshold && abs(y) >= abs(x) {
            state = .zooming
            return [.zoom(.begin)] + magnify(y)
        }
        guard max(abs(x), abs(y)) >= options.dragDistance else { return [] }
        state = .done
        if abs(x) > abs(y) { return [.action(x < 0 ? .left : .right)] }
        return [.action(y < 0 ? .up : .down)]
    }

    public mutating func advance(to time: TimeInterval) -> Event? {
        guard state == .pending, let deadline, time >= deadline else { return nil }
        state = .done
        return .action(.hold)
    }

    public mutating func up(at time: TimeInterval) -> [Event] {
        defer { self = ButtonGesture() }
        switch state {
        case .idle, .done: return []
        case .zooming: return [.zoom(.end)]
        case .pending:
            // A late hold timer must not turn a long press into a click.
            if let deadline, time >= deadline { return [.action(.hold)] }
            return [.action(.click)]
        }
    }

    public mutating func cancel() -> [Event] {
        defer { self = ButtonGesture() }
        return state == .zooming ? [.zoom(.cancel)] : []
    }

    private func magnify(_ vertical: Double) -> [Event] {
        guard vertical != 0 else { return [] }
        // HID movement is positive down; pinch magnification is positive in.
        let amount = -vertical * 0.0015 * options.zoomSpeed
        return [.zoom(.magnify(max(-0.25, min(0.25, amount))))]
    }
}
