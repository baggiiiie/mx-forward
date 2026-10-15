import Foundation

public struct ThumbGestureInterpreter {
    public enum Action: String, Codable, CaseIterable {
        case click, up, down, left, right
    }
    public private(set) var isPressed = false
    private var discardFirst = false
    private var performed = false
    private var x = 0.0
    private var y = 0.0
    private var threshold = 120.0

    public init() {}

    public mutating func down(sensitivity: Double = 1, discardFirstReport: Bool = false) {
        guard !isPressed else { return }
        precondition(sensitivity.isFinite && sensitivity > 0)
        self = ThumbGestureInterpreter()
        isPressed = true
        threshold /= sensitivity
        discardFirst = discardFirstReport
    }

    public mutating func move(dx: Int16, dy: Int16) -> Action? {
        guard isPressed, !performed else { return nil }
        if discardFirst {
            discardFirst = false
            return nil
        }
        x += Double(dx)
        y += Double(dy)
        guard max(abs(x), abs(y)) >= threshold else { return nil }
        performed = true
        if abs(x) > abs(y) { return x < 0 ? .left : .right }
        return y < 0 ? .up : .down
    }

    public mutating func up() -> Action? {
        guard isPressed else { return nil }
        defer { self = ThumbGestureInterpreter() }
        return performed ? nil : .click
    }

    public mutating func cancel() { self = ThumbGestureInterpreter() }
}
