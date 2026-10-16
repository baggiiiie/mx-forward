import ForwardCore
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
        [
            .wheel: p.wheelEnabled, .top: p.topZoomEnabled, .forward: p.forwardEnabled,
            .back: p.backEnabled, .gesture: p.thumbGesturesEnabled, .thumbWheel: true,
        ]
    }

    static func summaries(_ p: Preferences) -> [MouseButton: String] {
        func label(_ shortcut: Shortcut?) -> String { shortcut?.label ?? "No action" }
        let gestures = ThumbGestureInterpreter.Action.allCases
        let customGestures = gestures.filter {
            (p.thumbShortcuts[$0.rawValue]?.source ?? .defaultShortcut) != .defaultShortcut
        }
        let top =
            p.topClickAction == .shortcut
            ? p.topClickShortcut?.label ?? "Shortcut not set" : p.topClickAction.label
        return [
            .wheel:
                "\(Int((p.wheelSpeed * 100).rounded()))% · \(p.wheelMode == .unchanged ? (p.wheelNatural ? "Natural" : "Standard") : p.wheelMode.label)",
            .top: top,
            .thumbWheel: p.horizontalDirection == .unchanged
                ? "Native direction" : p.horizontalDirection.label,
            .forward: label(p.forwardClick.resolve(default: .forward))
                + (p.forwardHoldEnabled ? p.shortcut.map { " · hold \($0.label)" } ?? "" : ""),
            .back: label(p.backClick.resolve(default: .back)),
            .gesture: customGestures.isEmpty ? "Mission Control" : "\(customGestures.count) custom gestures",
        ]
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
        case .top: return "The button behind the wheel"
        case .thumbWheel: return "Horizontal scrolling under your thumb"
        case .forward: return "Front side button"
        case .back: return "Rear side button"
        case .gesture: return "Under your thumb · press or hold and move"
        }
    }

    @ViewBuilder private var content: some View {
        switch button {
        case .forward: forward
        case .back: back
        case .gesture: gesture
        case .top: top
        case .wheel: wheel
        case .thumbWheel: thumbWheel
        }
    }

    private func mappingRow(
        _ title: String, _ mapping: Binding<ShortcutMapping>, default shortcut: Shortcut?, resetHelp: String
    ) -> some View {
        ShortcutMappingRow(
            title: title, mapping: mapping, defaultShortcut: shortcut, resetHelp: resetHelp,
            onRecordingChanged: onRecordingChanged)
    }

    @ViewBuilder private var forward: some View {
        Section {
            Toggle("Use Forward button", isOn: $preferences.forwardEnabled)
        }
        Section {
            mappingRow(
                "Click", $preferences.forwardClick, default: .forward, resetHelp: "Restore Forward (⌘])")
        } header: {
            Text("Click")
        } footer: {
            Text("Click the shortcut, then press your keys. Fires on release.").inspectorFootnote()
        }
        .disabled(!preferences.forwardEnabled)
        Section {
            Toggle("Send a shortcut when held", isOn: $preferences.forwardHoldEnabled)
            if preferences.forwardHoldEnabled {
                LabeledContent("Shortcut") {
                    HStack {
                        ShortcutRecorder(
                            shortcut: $preferences.shortcut, onRecordingChanged: onRecordingChanged
                        )
                        .frame(height: 28)
                        if preferences.shortcut != nil {
                            Button("Clear") { preferences.shortcut = nil }
                        }
                    }
                }
                ValueSlider(
                    title: "Hold delay", value: $preferences.holdMilliseconds, range: 150...1500, step: 50,
                    accessibility: "Hold delay in milliseconds"
                ) { "\(Int($0)) ms" }
                VStack(alignment: .leading, spacing: 6) {
                    TimingPad(delay: preferences.holdMilliseconds, result: $testResult).frame(height: 40)
                    Text(testResult).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Hold")
        } footer: {
            Text("A hold sends the shortcut once, without also going Forward.").inspectorFootnote()
        }
        .disabled(!preferences.forwardEnabled)
    }

    @ViewBuilder private var back: some View {
        Section {
            Toggle("Use Back button", isOn: $preferences.backEnabled)
        }
        Section {
            mappingRow("Click", $preferences.backClick, default: .back, resetHelp: "Restore Back (⌘[)")
        } header: {
            Text("Click")
        } footer: {
            Text(
                "Click the shortcut, then press your keys. Clear disables the button; the arrow restores ⌘[."
            )
            .inspectorFootnote()
        }
        .disabled(!preferences.backEnabled)
    }

    @ViewBuilder private var gesture: some View {
        Section {
            Toggle("Use gesture button", isOn: $preferences.thumbGesturesEnabled)
        }
        Section {
            ForEach(ThumbGestureInterpreter.Action.allCases, id: \.self) { action in
                mappingRow(
                    action == .click ? "Click" : "Hold + \(action.rawValue)",
                    Binding(
                        get: { preferences.thumbShortcuts[action.rawValue] ?? ShortcutMapping() },
                        set: { preferences.thumbShortcuts[action.rawValue] = $0 }),
                    default: WindowNavigationOutput.currentShortcut(action),
                    resetHelp: "Use macOS \(WindowNavigationOutput.label(action)) shortcut")
            }
        } header: {
            Text("Actions")
        } footer: {
            Text(
                "Defaults follow macOS: click and up open Mission Control, down opens App Exposé, left and right switch desktops. Each press performs one action."
            ).inspectorFootnote()
        }
        .disabled(!preferences.thumbGesturesEnabled)
        Section {
            ValueSlider(
                title: "Sensitivity", value: $preferences.thumbSensitivity, range: 0.25...3, step: 0.05,
                accessibility: "Thumb gesture sensitivity", format: Self.percent)
        }
        .disabled(!preferences.thumbGesturesEnabled)
    }

    @ViewBuilder private var top: some View {
        Section {
            Toggle("Use top button", isOn: $preferences.topZoomEnabled)
        }
        Section {
            Picker("Action", selection: $preferences.topClickAction) {
                ForEach(TopClickAction.allCases) { action in Text(action.label).tag(action) }
            }
            if preferences.topClickAction == .shortcut {
                LabeledContent("Shortcut") {
                    HStack {
                        ShortcutRecorder(
                            shortcut: $preferences.topClickShortcut,
                            accessibilityLabel: "Top-button click keyboard shortcut",
                            onRecordingChanged: onRecordingChanged
                        )
                        .frame(height: 28)
                        if preferences.topClickShortcut != nil {
                            Button("Clear") { preferences.topClickShortcut = nil }
                        }
                    }
                }
            }
        } header: {
            Text("Click")
        }
        .disabled(!preferences.topZoomEnabled)
        Section {
            ValueSlider(
                title: "Zoom speed", value: $preferences.zoomSensitivity, range: 0.25...6, step: 0.05,
                accessibility: "Hold zoom speed", format: Self.percent)
            Button("Open zoom verification…", action: showZoomTest)
        } header: {
            Text("Hold + move up/down to zoom")
        } footer: {
            Text(
                "Higher speed needs less mouse movement. Zoom uses native pinch events in apps that support them."
            )
            .inspectorFootnote()
        }
        .disabled(!preferences.topZoomEnabled)
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
            Picker("Direction", selection: $preferences.horizontalDirection) {
                ForEach(HorizontalDirection.allCases) { direction in Text(direction.label).tag(direction) }
            }
            .pickerStyle(.radioGroup)
        } header: {
            Text("Horizontal scrolling")
        } footer: {
            Text("Keep current direction leaves the native setting alone. Pause restores it.")
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

extension Text {
    fileprivate func inspectorFootnote() -> some View {
        font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
