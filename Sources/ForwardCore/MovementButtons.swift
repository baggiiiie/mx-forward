/// Prevents two held gesture buttons from sharing the same movement report.
public struct MovementButtons {
    public enum Transition: Equatable {
        case begin(MouseControl)
        case finish(MouseControl)
        case cancel(MouseControl)
    }
    public private(set) var active: MouseControl?
    private var held = Set<MouseControl>()
    private var blocked = false

    public init() {}

    public mutating func update(_ control: MouseControl, down: Bool) -> Transition? {
        guard control.reportsMovement, down != held.contains(control) else { return nil }
        if down {
            held.insert(control)
            if let previous = active {
                active = nil
                blocked = true
                return .cancel(previous)
            }
            guard !blocked else { return nil }
            active = control
            return .begin(control)
        }
        held.remove(control)
        if held.isEmpty { blocked = false }
        guard active == control else { return nil }
        active = nil
        return .finish(control)
    }

    public mutating func cancel() { self = MovementButtons() }
}
