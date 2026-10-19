import ForwardCore
import MouseEngine
import SwiftUI

struct MouseConfigurator: View {
    @Binding var preferences: Preferences
    @Binding var selection: MouseButton
    @Binding var testResult: String
    var held: Set<MouseControl>
    var locked: Bool
    var onRecordingChanged: (Bool) -> Void
    var showZoomTest: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 6) {
                Spacer(minLength: 0)
                MouseIllustration(
                    selection: $selection, summaries: Self.summaries(preferences),
                    enabled: Self.enabled(preferences),
                    pressed: Set(MouseButton.allCases.filter { $0.control.map(held.contains) ?? false }))
                Text("Click a button on the mouse to configure it.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ButtonInspector(
                button: selection, preferences: $preferences, testResult: $testResult,
                onRecordingChanged: onRecordingChanged, showZoomTest: showZoomTest
            )
            .frame(width: 390)
            .disabled(locked)
        }
    }

    static func enabled(_ p: Preferences) -> [MouseButton: Bool] {
        var enabled: [MouseButton: Bool] = [.wheel: p.wheelEnabled]
        for button in MouseButton.allCases {
            if let control = button.control { enabled[button] = p.buttons[control].enabled }
        }
        return enabled
    }

    static func summaries(_ p: Preferences) -> [MouseButton: String] {
        var summaries: [MouseButton: String] = [
            .wheel:
                "\(ButtonInspector.percent(p.wheelSpeed)) · \(p.wheelMode == .unchanged ? (p.wheelNatural ? "Natural" : "Standard") : p.wheelMode.label)",
            .thumbWheel:
                "\(ButtonInspector.percent(p.horizontalSpeed)) · \(p.horizontalDirection == .unchanged ? "Native direction" : p.horizontalDirection.label)",
        ]
        for button in MouseButton.allCases {
            guard let control = button.control else { continue }
            let mapping = p.buttons[control]
            let others = ButtonSlot.allCases.filter { $0 != .click && !mapping[$0].isNone }
            var more = others.count
            if mapping.dragScroll { more -= 3 } else if mapping.verticalZoom { more -= 1 }
            summaries[button] = mapping.click.label + (more > 0 ? " +\(more)" : "")
        }
        return summaries
    }
}

struct ButtonInspector: View {
    var button: MouseButton
    @Binding var preferences: Preferences
    @Binding var testResult: String
    var onRecordingChanged: (Bool) -> Void
    var showZoomTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: button.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.gradient)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(button.title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 4)
            Form { content }
                .formStyle(.grouped)
        }
        .id(button)
    }

    private var subtitle: String {
        switch button {
        case .wheel: return "Speed, acceleration, and ratchet feel"
        case .wheelButton: return "Press the main wheel"
        case .top: return "The button behind the wheel"
        case .thumbWheel: return "Horizontal scrolling under your thumb"
        case .forward: return "Front side button"
        case .back: return "Rear side button"
        case .gesture: return "Under your thumb"
        }
    }

    @ViewBuilder private var content: some View {
        switch button {
        case .wheel: wheel
        case .thumbWheel: thumbWheel
        default: if let control = button.control { ClickableButtonForm(control: control, inspector: self) }
        }
    }

    @ViewBuilder private var wheel: some View {
        Section {
            Toggle("Control main wheel", isOn: $preferences.wheelEnabled)
        } footer: {
            Text("Off leaves native scrolling and the wheel’s current mode untouched.").inspectorFootnote()
        }
        Section {
            ValueSlider(
                title: "Scroll speed", value: $preferences.wheelSpeed, range: 0.25...6, step: 0.05,
                accessibility: "Main wheel scroll speed", format: Self.percent)
            ValueSlider(
                title: "Acceleration", value: $preferences.wheelAcceleration, range: 0...2, step: 0.05,
                accessibility: "Main wheel acceleration strength"
            ) { $0 == 0 ? "Off" : Self.percent($0) }
            Toggle("Natural scrolling", isOn: $preferences.wheelNatural)
        } header: {
            Text("Scrolling")
        } footer: {
            Text("Slow scrolling uses your baseline speed; faster spins scroll farther.").inspectorFootnote()
        }
        .disabled(!preferences.wheelEnabled)
        Section {
            Picker("Wheel mode", selection: $preferences.wheelMode) {
                ForEach(WheelMode.allCases) { mode in Text(mode.label).tag(mode) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Feel")
        } footer: {
            Text(
                "Ratchet stays notched. Free-spin removes the notches. Keep current mode preserves SmartShift."
            ).inspectorFootnote()
        }
        .disabled(!preferences.wheelEnabled)
    }

    @ViewBuilder private var thumbWheel: some View {
        Section {
            ValueSlider(
                title: "Scroll speed", value: $preferences.horizontalSpeed, range: 0.25...6, step: 0.05,
                accessibility: "Thumb wheel scroll speed", format: Self.percent)
            Picker("Direction", selection: $preferences.horizontalDirection) {
                ForEach(HorizontalDirection.allCases) { direction in Text(direction.label).tag(direction) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Horizontal scrolling")
        } footer: {
            Text(
                "100% keeps native scrolling. Other speeds use the selected multiplier without added acceleration. Pause restores your original settings."
            )
            .inspectorFootnote()
        }
    }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

struct ValueSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var step: Double
    var accessibility: String
    var format: (Double) -> String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(value: $value, in: range, step: step).labelsHidden().accessibilityLabel(accessibility)
                Text(format(value)).monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }
}

/// Click, hold, and drag settings shared by every clickable button.
private struct ClickableButtonForm: View {
    var control: MouseControl
    var inspector: ButtonInspector

    private var mapping: Binding<ButtonMapping> { inspector.$preferences.buttons[control] }
    private var value: ButtonMapping { mapping.wrappedValue }
    private var dragsByDistance: Bool {
        ButtonSlot.directions.contains {
            !value[$0].isNone && value[$0].kind != .zoom && value[$0].kind != .scroll
        }
    }

    var body: some View {
        Section {
            Toggle("Use this button", isOn: mapping.enabled)
        } footer: {
            if control == .middle {
                Text("While on, the wheel button no longer middle-clicks unless an action says so.")
                    .inspectorFootnote()
            }
        }
        Group {
            Section {
                ForEach([ButtonSlot.click, .hold], id: \.self, content: row)
            } header: {
                Text("Press")
            } footer: {
                Text(
                    "Click fires on release. Hold fires once after the hold delay, and then the click doesn’t."
                )
                .inspectorFootnote()
            }
            Section {
                ForEach(ButtonSlot.directions, id: \.self, content: row)
            } header: {
                Text("Hold and drag")
            } footer: {
                Text(
                    "Hold the button and move the mouse. Scroll & navigate links all four directions and moves both the cursor and content. Other drag actions keep the pointer still."
                ).inspectorFootnote()
            }
            timing
            Section {
                Button("Restore defaults") { mapping.wrappedValue = .defaults(for: control) }
                    .disabled(value == .defaults(for: control))
            }
        }
        .disabled(!value.enabled)
    }

    private func title(_ slot: ButtonSlot) -> String {
        switch slot {
        case .click: return "Click"
        case .hold: return "Hold"
        case .up: return "Drag up"
        case .down: return "Drag down"
        case .left: return "Drag left"
        case .right: return "Drag right"
        }
    }

    private func row(_ slot: ButtonSlot) -> some View {
        let kind = Binding(
            get: { value[slot].kind },
            set: { kind in
                let shortcut = value[slot].shortcut ?? ButtonMapping.defaults(for: control)[slot].shortcut
                mapping.wrappedValue.set(
                    ButtonAction(kind, shortcut: shortcut, modifiers: value[slot].modifiers), for: slot)
            })
        let shortcut = Binding(
            get: { value[slot].shortcut },
            set: { mapping.wrappedValue[slot] = .shortcut($0) })
        let modifiers = Binding(
            get: { value[slot].modifiers },
            set: { mapping.wrappedValue[slot] = ButtonAction(.modifierClick, modifiers: $0) })
        return VStack(alignment: .trailing, spacing: 6) {
            Picker(title(slot), selection: kind) {
                ForEach(ButtonAction.Kind.choices(for: slot)) { kind in Text(kind.label).tag(kind) }
            }
            if value[slot].kind == .shortcut {
                ShortcutRecorder(
                    shortcut: shortcut,
                    accessibilityLabel: "\(inspector.button.title) \(title(slot).lowercased()) shortcut",
                    onRecordingChanged: inspector.onRecordingChanged
                )
                .frame(width: 180, height: 28)
            } else if value[slot].kind == .modifierClick {
                ModifierRecorder(
                    modifiers: modifiers,
                    accessibilityLabel: "\(inspector.button.title) \(title(slot).lowercased()) modifiers",
                    onRecordingChanged: inspector.onRecordingChanged
                )
                .frame(width: 210, height: 28)
                Text("Hold the modifier keys, then release to save. Sends a left click at the pointer.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var timing: some View {
        if !value.hold.isNone || dragsByDistance || value.verticalZoom || value.dragScroll {
            Section {
                if !value.hold.isNone {
                    ValueSlider(
                        title: "Hold delay", value: mapping.holdMilliseconds, range: 150...1500, step: 50,
                        accessibility: "Hold delay in milliseconds"
                    ) { "\(Int($0)) ms" }
                    VStack(alignment: .leading, spacing: 6) {
                        TimingPad(delay: value.holdMilliseconds, result: inspector.$testResult).frame(
                            height: 40)
                        Text(inspector.testResult).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if dragsByDistance {
                    ValueSlider(
                        title: "Drag sensitivity", value: mapping.dragSensitivity, range: 0.25...3,
                        step: 0.05,
                        accessibility: "Drag sensitivity", format: ButtonInspector.percent)
                }
                if value.dragScroll {
                    ValueSlider(
                        title: "Scroll speed", value: mapping.dragSensitivity, range: 0.25...3,
                        step: 0.05, accessibility: "Drag scroll speed", format: ButtonInspector.percent)
                }
                if value.verticalZoom {
                    ValueSlider(
                        title: "Zoom speed", value: mapping.zoomSpeed, range: 0.25...6, step: 0.05,
                        accessibility: "Zoom speed", format: ButtonInspector.percent)
                    Button("Open zoom verification…", action: inspector.showZoomTest)
                }
            } header: {
                Text("Timing")
            } footer: {
                if value.verticalZoom {
                    Text("Zoom uses native pinch events in apps that support them.").inspectorFootnote()
                }
            }
        }
    }
}

extension Text {
    fileprivate func inspectorFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
