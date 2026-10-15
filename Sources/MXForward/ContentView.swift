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
                        Text("Click Forward: ⌘]. Click Back: ⌘[. Navigation fires on release.")
                            .font(.callout).foregroundStyle(.secondary)
                        Toggle("Hold Forward for a shortcut", isOn: $model.preferences.forwardHoldEnabled)
                            .disabled(!model.preferences.forwardEnabled)
                        if model.preferences.forwardHoldEnabled {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Shortcut").frame(width: 80, alignment: .leading)
                                    ShortcutRecorder(shortcut: $model.preferences.shortcut)
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
                }.disabled(model.enabled || model.busy || model.needsRelease)
                Toggle("Test mode — show actions without sending them", isOn: $model.preferences.testMode)
                    .disabled(model.enabled || model.busy || model.needsRelease)
                Text(
                    "The mouse connects automatically. Enable once to resume after launch or reconnect. Pause keeps mappings off."
                )
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                GroupBox("Thumb-button gestures") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Window navigation", isOn: $model.preferences.thumbGesturesEnabled)
                        Text(
                            "Click or move up: Mission Control. Move down: App Exposé. Move left/right: switch desktops."
                        )
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Text(
                            "Hold the thumb button while moving. Each press performs one action using your macOS keyboard shortcuts."
                        )
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Text("Gesture sensitivity")
                            Slider(value: $model.preferences.thumbSensitivity, in: 0.25...3, step: 0.05)
                                .accessibilityLabel("Thumb gesture sensitivity")
                            Text("\(Int(model.preferences.thumbSensitivity * 100))%")
                                .monospacedDigit().frame(width: 48, alignment: .trailing)
                        }
                    }.padding(4)
                }.disabled(model.enabled || model.busy || model.needsRelease)
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
                                    accessibilityLabel: "Top-button click keyboard shortcut"
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
                }.disabled(model.enabled || model.busy || model.needsRelease)
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
                    "Side buttons use ⌘[ and ⌘]. Top-button zoom uses native pinch events in apps that support them."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(width: 560, height: min(820, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var accessibilityLabel = "Hold keyboard shortcut"
    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.bezelStyle = .rounded
        view.onRecord = { shortcut = $0 }
        return view
    }
    func updateNSView(_ view: RecorderButton, context: Context) {
        view.isEnabled = context.environment.isEnabled
        view.shortcutTitle = shortcut?.label ?? "Record shortcut…"
        view.updateTitle()
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

final class RecorderButton: NSButton {
    private var recording = false
    var shortcutTitle = "Record shortcut…"
    var onRecord: (Shortcut) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func beginRecording() {
        window?.makeFirstResponder(self)
        recording = true
        updateTitle()
    }
    func updateTitle() {
        if !isEnabled { recording = false }
        title = recording ? "Press shortcut… (Esc cancels)" : shortcutTitle
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, isEnabled else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard recording, isEnabled else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }
    private func capture(_ event: NSEvent) {
        if event.keyCode == 53
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            recording = false
            updateTitle()
            return
        }
        guard !event.isARepeat else { return }
        recording = false
        onRecord(Shortcut.recorded(from: event))
    }
    override func resignFirstResponder() -> Bool {
        recording = false
        updateTitle()
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        if window == nil {
            recording = false
            updateTitle()
        }
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
                ? "Click detected → Forward (preview only)"
                : "Hold detected → shortcut once; no Forward (preview only)")
    }
    override func viewDidMoveToWindow() {
        if window == nil {
            timer?.invalidate()
            machine.cancel()
        }
    }
}
