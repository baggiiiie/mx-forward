import AppKit
import ForwardCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "computermouse.fill").font(.largeTitle).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MX Forward").font(.title2.weight(.semibold))
                        Text("Side buttons, thumb gestures and zoom").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("MVP · Bolt").font(.caption).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.status, systemImage: model.enabled ? "checkmark.circle.fill" : "circle")
                            .accessibilityIdentifier("connectionStatus")
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Discover mouse") { model.discover() }
                                .disabled(model.enabled || model.busy || model.needsRelease)
                            Spacer()
                            if model.enabled || model.needsRelease || model.preferences.resumeMappings {
                                Button(model.needsRelease ? "Retry restoring buttons" : "Pause") {
                                    Task { await model.pause() }
                                }.disabled(model.busy)
                            } else {
                                Button("Enable") { Task { await model.enable() } }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!model.canEnable)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                GroupBox("Side buttons") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Toggle("Forward", isOn: $model.preferences.forwardEnabled)
                            Toggle("Back", isOn: $model.preferences.backEnabled)
                        }
                        ShortcutMappingRow(
                            title: "Forward click", mapping: $model.preferences.forwardClick,
                            defaultShortcut: .forward, resetHelp: "Restore Forward (⌘])",
                            onRecordingChanged: model.setRecordingShortcut
                        )
                        .disabled(!model.preferences.forwardEnabled)
                        ShortcutMappingRow(
                            title: "Back click", mapping: $model.preferences.backClick,
                            defaultShortcut: .back, resetHelp: "Restore Back (⌘[)",
                            onRecordingChanged: model.setRecordingShortcut
                        )
                        .disabled(!model.preferences.backEnabled)
                        Text("Click a shortcut, then press your keys. Side-button clicks fire on release.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("Hold Forward for a shortcut", isOn: $model.preferences.forwardHoldEnabled)
                            .disabled(!model.preferences.forwardEnabled)
                        if model.preferences.forwardHoldEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Shortcut").frame(width: 80, alignment: .leading)
                                    ShortcutRecorder(
                                        shortcut: $model.preferences.shortcut,
                                        onRecordingChanged: model.setRecordingShortcut
                                    )
                                    .frame(height: 32)
                                    if model.preferences.shortcut != nil {
                                        Button("Clear") { model.preferences.shortcut = nil }
                                    }
                                }
                                HStack {
                                    Text("Hold delay").frame(width: 80, alignment: .leading)
                                    Slider(
                                        value: $model.preferences.holdMilliseconds, in: 150...1500, step: 50
                                    )
                                    .accessibilityLabel("Hold delay in milliseconds")
                                    Text("\(Int(model.preferences.holdMilliseconds)) ms").monospacedDigit()
                                        .frame(width: 65, alignment: .trailing)
                                }
                                Text("A hold sends the shortcut once, without also going Forward.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }.disabled(!model.preferences.forwardEnabled)
                        }
                    }.padding(4)
                }.disabled(model.busy || model.needsRelease)
                Toggle("Test mode — show actions without sending them", isOn: $model.preferences.testMode)
                    .disabled(model.busy || model.needsRelease)
                Text(
                    "Settings apply automatically while enabled. Click a shortcut and press your keys to change it. Pause turns mappings off."
                )
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                GroupBox("Thumb-button gestures") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Window navigation", isOn: $model.preferences.thumbGesturesEnabled)
                        Text(
                            "Defaults: click/up opens Mission Control, down opens App Exposé, left/right switches desktops."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Click any shortcut below to record your own. Hold the thumb button while moving; each press performs one action."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        ForEach(ThumbGestureInterpreter.Action.allCases, id: \.self) { action in
                            ShortcutMappingRow(
                                title: action == .click ? "Click" : "Hold + \(action.rawValue)",
                                mapping: Binding(
                                    get: {
                                        model.preferences.thumbShortcuts[action.rawValue] ?? ShortcutMapping()
                                    },
                                    set: { model.preferences.thumbShortcuts[action.rawValue] = $0 }),
                                defaultShortcut: WindowNavigationOutput.currentShortcut(action),
                                resetHelp: "Use macOS \(WindowNavigationOutput.label(action)) shortcut",
                                onRecordingChanged: model.setRecordingShortcut)
                        }
                        HStack {
                            Text("Gesture sensitivity")
                            Slider(value: $model.preferences.thumbSensitivity, in: 0.25...3, step: 0.05)
                                .accessibilityLabel("Thumb gesture sensitivity")
                            Text("\(Int(model.preferences.thumbSensitivity * 100))%")
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }.padding(4)
                }.disabled(model.busy || model.needsRelease)
                GroupBox("Top button") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable top button", isOn: $model.preferences.topZoomEnabled)
                        Picker("Single click", selection: $model.preferences.topClickAction) {
                            ForEach(TopClickAction.allCases) { action in
                                Text(action.label).tag(action)
                            }
                        }
                        if model.preferences.topClickAction == .shortcut {
                            HStack {
                                ShortcutRecorder(
                                    shortcut: $model.preferences.topClickShortcut,
                                    accessibilityLabel: "Top-button click keyboard shortcut",
                                    onRecordingChanged: model.setRecordingShortcut
                                )
                                .frame(height: 32)
                                if model.preferences.topClickShortcut != nil {
                                    Button("Clear") { model.preferences.topClickShortcut = nil }
                                }
                            }
                        }
                        Text("Hold + move up/down to zoom. Higher speed needs less mouse movement.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("Hold zoom speed")
                            Slider(value: $model.preferences.zoomSensitivity, in: 0.25...6, step: 0.05)
                                .accessibilityLabel("Hold zoom speed")
                            Text("\(Int(model.preferences.zoomSensitivity * 100))%")
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }.padding(4)
                }.disabled(model.busy || model.needsRelease)
                GroupBox("Main scroll wheel") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Control main wheel", isOn: $model.preferences.wheelEnabled)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Scroll speed")
                                Slider(value: $model.preferences.wheelSpeed, in: 0.25...6, step: 0.05)
                                    .accessibilityLabel("Main wheel scroll speed")
                                Text("\(Int(model.preferences.wheelSpeed * 100))%")
                                    .monospacedDigit().frame(width: 48, alignment: .trailing)
                            }
                            Toggle("Natural scrolling", isOn: $model.preferences.wheelNatural)
                            HStack {
                                Text("Acceleration")
                                Slider(value: $model.preferences.wheelAcceleration, in: 0...2, step: 0.05)
                                    .accessibilityLabel("Main wheel acceleration strength")
                                Text(
                                    model.preferences.wheelAcceleration == 0
                                        ? "Off"
                                        : "\(Int((model.preferences.wheelAcceleration * 100).rounded()))%"
                                )
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                            }
                            Text(
                                "Slow scrolling uses your baseline speed. Faster spins scroll farther. Set acceleration to 0% to turn it off."
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            Picker("Wheel mode", selection: $model.preferences.wheelMode) {
                                ForEach(WheelMode.allCases) { mode in Text(mode.label).tag(mode) }
                            }
                            Text(
                                "Ratchet stays notched. Free-spin removes the notches. Keep current mode preserves your mouse’s existing SmartShift behavior."
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }.disabled(!model.preferences.wheelEnabled)
                        Text(
                            "Applies to this mouse’s main wheel. Pause restores native scrolling and the previous wheel mode."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }.padding(4)
                }.disabled(model.busy || model.needsRelease)
                GroupBox("Horizontal scrolling") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Thumb-wheel direction", selection: $model.preferences.horizontalDirection) {
                            ForEach(HorizontalDirection.allCases) { direction in
                                Text(direction.label).tag(direction)
                            }
                        }
                        Text(
                            "Choose the left/right scroll direction for the thumb wheel. Changes apply automatically while enabled."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }.padding(4)
                }.disabled(model.busy || model.needsRelease)
                Button("Open zoom verification") { model.showZoomTest() }
                GroupBox("Try the timing") {
                    VStack(alignment: .leading, spacing: 8) {
                        TimingPad(delay: model.preferences.holdMilliseconds, result: $model.testResult)
                            .frame(height: 48)
                        Text(model.testResult).font(.callout).foregroundStyle(.secondary)
                        Text(model.lastAction).font(.callout).accessibilityIdentifier("lastMouseAction")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(
                            model.inputMonitoring
                                ? "Input Monitoring granted" : "Input Monitoring not granted",
                            systemImage: model.inputMonitoring ? "checkmark.circle" : "circle")
                        Spacer()
                        Button("Open settings") { model.openPermission("Privacy_ListenEvent") }
                    }
                    HStack {
                        Label(
                            model.accessibility
                                ? "Accessibility ready" : "Accessibility needed for live actions",
                            systemImage: model.accessibility ? "checkmark.circle" : "circle")
                        Spacer()
                        Button("Open settings") { model.openPermission("Privacy_Accessibility") }
                    }
                    if model.logitechRunning {
                        Label(
                            "Logitech’s background agent is running. Stop it before enabling.",
                            systemImage: "exclamationmark.circle"
                        )
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(
                        "Accessibility is required for live actions. Add Input Monitoring only if discovery is blocked. Restart after changing permissions. Closing this window keeps the app in the menu bar."
                    )
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.font(.callout)
                DisclosureGroup("Diagnostics", isExpanded: $model.diagnostics) {
                    ScrollView {
                        Text(
                            model.log.isEmpty
                                ? "Discover the mouse to begin."
                                : model.log.suffix(15).joined(separator: "\n")
                        )
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 130)
                }
                Text(
                    "Top-button zoom uses native pinch events in apps that support them."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 560, height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
    }
}

struct TimingPad: NSViewRepresentable {
    var delay: Double
    @Binding var result: String
    func makeNSView(context: Context) -> TimingPadView {
        let view = TimingPadView()
        view.onResult = { result = $0 }
        return view
    }
    func updateNSView(_ view: TimingPadView, context: Context) { view.delay = delay }
}

final class TimingPadView: NSView {
    var delay = 400.0
    var onResult: (String) -> Void = { _ in }
    private var machine = PressInterpreter()
    private var timer: Timer?
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Press or hold to test timing")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
        let text: NSString = "Click or hold here to test"
        let style: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: style)
        text.draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: style)
    }
    override func mouseDown(with event: NSEvent) {
        machine.cancel()
        timer?.invalidate()
        machine.down(at: ProcessInfo.processInfo.systemUptime, threshold: delay / 1000)
        onResult("Pressed…")
        let next = Timer(timeInterval: delay / 1000, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let action = self.machine.advance(to: ProcessInfo.processInfo.systemUptime) {
                self.show(action)
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
    override func mouseUp(with event: NSEvent) {
        timer?.invalidate()
        timer = nil
        if let action = machine.up(at: ProcessInfo.processInfo.systemUptime) { show(action) }
    }
    private func show(_ action: PressInterpreter.Action) {
        onResult(
            action == .forward
                ? "Click detected (preview only)"
                : "Hold detected → shortcut once; no Forward (preview only)")
    }
    override func viewDidMoveToWindow() {
        if window == nil {
            timer?.invalidate()
            machine.cancel()
        }
    }
}
