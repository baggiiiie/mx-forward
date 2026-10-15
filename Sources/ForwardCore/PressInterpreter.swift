import Foundation

/// Separates clicks from holds using the time supplied by the caller.
public struct PressInterpreter {
    public enum Action: Equatable { case forward, shortcut }
    private enum State {
        case idle
        case waiting(deadline: TimeInterval)
        case held
    }
    private var state: State = .idle
    public init() {}

    public var isPressed: Bool {
        if case .idle = state { return false }
        return true
    }

    public mutating func down(at time: TimeInterval, threshold: TimeInterval) {
        guard case .idle = state else { return }
        precondition(threshold.isFinite && threshold > 0)
        state = .waiting(deadline: time + threshold)
    }

    public mutating func advance(to time: TimeInterval) -> Action? {
        guard case .waiting(let deadline) = state, time >= deadline else { return nil }
        state = .held
        return .shortcut
    }

    public mutating func up(at time: TimeInterval) -> Action? {
        defer { state = .idle }
        guard case .waiting(let deadline) = state else { return nil }
        // A delayed timer must never turn a long press into Forward.
        return time >= deadline ? .shortcut : .forward
    }

    public mutating func cancel() { state = .idle }
}
