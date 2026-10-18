import ForwardCore

extension Preferences {
    /// Apply only the fields the editor changed, keeping newer settings from elsewhere.
    package func applyingEdits(from base: Preferences, to edited: Preferences) -> Preferences {
        var result = self
        for key in [\Preferences.testMode, \.wheelEnabled, \.wheelNatural] {
            copyChange(key, from: base, to: edited, into: &result)
        }
        for key in [\Preferences.wheelSpeed, \.wheelAcceleration] {
            copyChange(key, from: base, to: edited, into: &result)
        }
        copyChange(\.wheelMode, from: base, to: edited, into: &result)
        copyChange(\.horizontalDirection, from: base, to: edited, into: &result)
        for control in MouseControl.allCases {
            var mapping = result.buttons[control]
            let before = base.buttons[control]
            let after = edited.buttons[control]
            copyChange(\.enabled, from: before, to: after, into: &mapping)
            for key in [\ButtonMapping.holdMilliseconds, \.dragSensitivity, \.zoomSpeed] {
                copyChange(key, from: before, to: after, into: &mapping)
            }
            for slot in ButtonSlot.allCases where before[slot] != after[slot] {
                mapping.set(after[slot], for: slot)
            }
            result.buttons[control] = mapping
        }
        return result.normalized()
    }
}

private func copyChange<Root, Value: Equatable>(
    _ key: WritableKeyPath<Root, Value>, from base: Root, to edited: Root, into result: inout Root
) {
    if base[keyPath: key] != edited[keyPath: key] { result[keyPath: key] = edited[keyPath: key] }
}
