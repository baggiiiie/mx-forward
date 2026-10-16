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

public enum DragScrollAction: Equatable {
    case begin
    case move(x: Int32, y: Int32)
    case end
    case cancel
}

/// Recognizes clicks, holds, directional drags, zooming, and drag scrolling.
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
        public var dragScroll: Bool
        public var scrollSpeed: Double

        public init(
            holdDelay: TimeInterval? = nil, dragDistance: Double = 120, verticalZoom: Bool = false,
            zoomSpeed: Double = 1, discardFirstReport: Bool = false,
            dragScroll: Bool = false, scrollSpeed: Double = 1
        ) {
            self.holdDelay = holdDelay
            self.dragDistance = dragDistance
            self.verticalZoom = verticalZoom
            self.zoomSpeed = zoomSpeed
            self.discardFirstReport = discardFirstReport
            self.dragScroll = dragScroll
            self.scrollSpeed = scrollSpeed
        }
    }

    public enum Event: Equatable {
        case action(ButtonSlot)
        case zoom(ZoomAction)
        case scroll(DragScrollAction)
        case pointer(dx: Int16, dy: Int16)
    }

    private enum State { case idle, pending, zooming, scrolling, done }
    private static let continuousDragThreshold = 20.0

    private var state = State.idle
    private var options = Options()
    private var deadline: TimeInterval?
    private var discardFirst = false
    private var x = 0.0
    private var y = 0.0
    private var scrollX = 0.0
    private var scrollY = 0.0

    public init() {}

    public var isPressed: Bool { state != .idle }

    public mutating func down(at time: TimeInterval, options: Options) {
        guard state == .idle else { return }
        precondition(options.dragDistance.isFinite && options.dragDistance > 0)
        self = ButtonGesture()
        state = .pending
        self.options = options
        self.options.scrollSpeed = options.scrollSpeed.isFinite ? max(0.25, min(3, options.scrollSpeed)) : 1
        deadline = options.holdDelay.map { time + $0 }
        discardFirst = options.discardFirstReport
    }

    public mutating func move(dx: Int16, dy: Int16) -> [Event] {
        guard state != .idle else { return [] }
        if discardFirst {
            discardFirst = false
            return []
        }
        let pointer: [Event] = options.dragScroll && (dx != 0 || dy != 0) ? [.pointer(dx: dx, dy: dy)] : []
        return pointer + movement(dx: dx, dy: dy)
    }

    private mutating func movement(dx: Int16, dy: Int16) -> [Event] {
        guard state == .pending || state == .zooming || state == .scrolling else { return [] }
        if state == .scrolling { return scroll(Double(dx), Double(dy)) }
        if state == .zooming { return magnify(Double(dy)) }
        x += Double(dx)
        y += Double(dy)
        if options.dragScroll {
            guard max(abs(x), abs(y)) >= Self.continuousDragThreshold else { return [] }
            state = .scrolling
            return [.scroll(.begin)] + scroll(x, y)
        }
        if options.verticalZoom && abs(y) >= Self.continuousDragThreshold && abs(y) >= abs(x) {
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
        case .scrolling: return [.scroll(.end)]
        case .pending:
            // A late hold timer must not turn a long press into a click.
            if let deadline, time >= deadline { return [.action(.hold)] }
            return [.action(.click)]
        }
    }

    public mutating func cancel() -> [Event] {
        defer { self = ButtonGesture() }
        if state == .scrolling { return [.scroll(.cancel)] }
        return state == .zooming ? [.zoom(.cancel)] : []
    }

    private mutating func scroll(_ dx: Double, _ dy: Double) -> [Event] {
        // Content follows the hand, like natural trackpad scrolling.
        scrollX += dx * options.scrollSpeed
        scrollY += dy * options.scrollSpeed
        let px = Int32(scrollX.rounded(.towardZero))
        let py = Int32(scrollY.rounded(.towardZero))
        scrollX -= Double(px)
        scrollY -= Double(py)
        return px == 0 && py == 0 ? [] : [.scroll(.move(x: px, y: py))]
    }

    private func magnify(_ vertical: Double) -> [Event] {
        guard vertical != 0 else { return [] }
        // HID movement is positive down; pinch magnification is positive in.
        let amount = -vertical * 0.0015 * options.zoomSpeed
        return [.zoom(.magnify(max(-0.25, min(0.25, amount))))]
    }
}
