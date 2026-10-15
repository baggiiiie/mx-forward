import Foundation

/// Tracks Back and Forward independently.
public struct SideButtonInterpreter {
    public enum Action: Equatable { case back, forward, shortcut }
    private var pressed = Set<MouseControl>()
    private var forwardHold = PressInterpreter()

    public init() {}
    public func isPressed(_ control: MouseControl) -> Bool { pressed.contains(control) }

    public mutating func update(
        _ control: MouseControl, down: Bool, at time: TimeInterval,
        holdThreshold: TimeInterval? = nil
    ) -> Action? {
        guard control == .back || control == .forward,
            down != pressed.contains(control)
        else { return nil }
        if down { pressed.insert(control) } else { pressed.remove(control) }
        if control == .back { return down ? nil : .back }
        if down {
            if let holdThreshold { forwardHold.down(at: time, threshold: holdThreshold) }
            return nil
        }
        guard forwardHold.isPressed else { return .forward }
        return forwardHold.up(at: time).map { $0 == .forward ? .forward : .shortcut }
    }

    public mutating func advance(to time: TimeInterval) -> Action? {
        forwardHold.advance(to: time).map { _ in .shortcut }
    }

    public mutating func cancel() {
        pressed.removeAll()
        forwardHold.cancel()
    }
}
