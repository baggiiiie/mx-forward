import Foundation

public enum ZoomAction: Equatable {
    case click
    case begin
    case magnify(Double)
    case end
    case cancel
}

/// Converts held mouse movement into one continuous pinch gesture.
public struct ZoomInterpreter {
    public private(set) var isPressed = false
    private var discardFirst = false
    private var x = 0.0
    private var y = 0.0
    private var moved = false
    private var zooming = false
    private var sensitivity = 1.0
    private let threshold = 20.0

    public init() {}

    public mutating func down(sensitivity: Double = 1, discardFirstReport: Bool = false) {
        guard !isPressed else { return }
        self = ZoomInterpreter()
        isPressed = true
        self.sensitivity = sensitivity
        discardFirst = discardFirstReport
    }

    public mutating func move(dx: Int16, dy: Int16) -> [ZoomAction] {
        guard isPressed else { return [] }
        if discardFirst {
            discardFirst = false
            return []
        }
        x += Double(dx)
        y += Double(dy)
        moved = moved || hypot(x, y) >= threshold
        guard moved else { return [] }

        var actions: [ZoomAction] = []
        let vertical: Double
        if !zooming {
            guard abs(y) >= threshold else { return [] }
            zooming = true
            actions.append(.begin)
            vertical = y
        } else {
            vertical = Double(dy)
        }
        if vertical != 0 {
            // HID movement is positive down; pinch magnification is positive in.
            let amount = -vertical * 0.0015 * sensitivity
            actions.append(.magnify(max(-0.25, min(0.25, amount))))
        }
        return actions
    }

    public mutating func up() -> [ZoomAction] {
        guard isPressed else { return [] }
        defer { self = ZoomInterpreter() }
        if zooming { return [.end] }
        return moved ? [] : [.click]
    }

    public mutating func cancel() -> [ZoomAction] {
        defer { self = ZoomInterpreter() }
        return zooming ? [.cancel] : []
    }
}
