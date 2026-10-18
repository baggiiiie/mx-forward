import AppKit
import ForwardCore
import MouseEngine
import SettingsClient
import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case buttons = "Buttons"
    case json = "JSON"
    case setup = "Setup"
    var id: Self { self }
}

final class WindowState: ObservableObject {
    @Published var tab = MainTab.buttons
    @Published var selection = MouseButton.forward
}

struct ContentView: View {
    @ObservedObject var model: SettingsModel
    @StateObject private var window = WindowState()
    @StateObject private var editor = ConfigEditorState()

    var body: some View {
        VStack(spacing: 0) {
            header
            banners
            Divider()
            Group {
                switch window.tab {
                case .buttons:
                    MouseConfigurator(
                        preferences: $model.preferences, selection: $window.selection,
                        testResult: $model.testResult, held: model.heldControls,
                        locked: !model.agentAvailable || model.busy || model.needsRelease,
                        onRecordingChanged: model.setRecordingShortcut, showZoomTest: model.showZoomTest)
                case .json: ConfigEditorView(model: model, state: editor).disabled(!model.agentAvailable)
                case .setup: SetupView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 990, minHeight: 650)
    }

    private var stateBadge: (String, Color) {
        if model.needsRelease { return ("Needs restore", .red) }
        if model.enabled { return model.preferences.testMode ? ("Test mode", .orange) : ("Active", .green) }
        if model.busy { return ("Working…", .blue) }
        return model.connected ? ("Paused", .secondary) : ("Not connected", .secondary)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "computermouse.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("MX Master 3S").font(.headline)
                    let badge = stateBadge
                    Text(badge.0)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(badge.1.opacity(0.18)))
                        .foregroundStyle(badge.1)
                }
                Text(model.status)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .accessibilityIdentifier("connectionStatus")
            }
            .frame(width: 300, alignment: .leading)
            Spacer()
            Picker("Section", selection: $window.tab) {
                ForEach(MainTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            Spacer()
            HStack(spacing: 12) {
                Toggle("Test mode", isOn: $model.preferences.testMode)
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Show actions without sending them")
                    .disabled(!model.agentAvailable || model.busy || model.needsRelease)
                if model.enabled || model.needsRelease || model.preferences.resumeMappings {
                    Button(model.needsRelease ? "Retry restoring" : "Pause") {
                        Task { await model.pause() }
                    }
                    .disabled(model.busy)
                } else {
                    Button("Enable") { Task { await model.enable() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canEnable)
                }
            }
            .frame(width: 300, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var banners: some View {
        if model.logitechRunning {
            Banner(
                text:
                    "Logitech’s background agent is running. Stop it with ./scripts/logitech-session.sh stop before enabling.",
                symbol: "exclamationmark.triangle.fill", color: .orange)
        }
        if !model.accessibility && !model.preferences.testMode {
            Banner(
                text: "Accessibility permission is needed to send live actions.",
                symbol: "lock.fill", color: .orange, action: "Open Settings"
            ) { model.openPermission("Privacy_Accessibility") }
        }
        if let error = model.configError, window.tab != .json {
            Banner(
                text: "config.json: \(error)", symbol: "curlybraces", color: .red, action: "Show JSON"
            ) { window.tab = .json }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.secondary)
            Text(model.lastAction).accessibilityIdentifier("lastMouseAction")
            Spacer()
            Text("Settings apply automatically while enabled.").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
    }
}

private struct Banner: View {
    var text: String
    var symbol: String
    var color: Color
    var action: String?
    var perform: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action { Button(action, action: perform).controlSize(.small) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
    }
}

struct SetupView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Status") {
                    Text(model.status).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Move the mouse to wake it if discovery stalls.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Discover mouse") { model.discover() }
                        .disabled(!model.agentAvailable || model.enabled || model.busy || model.needsRelease)
                }
            }
            Section {
                permissionRow(
                    model.accessibility ? "Accessibility ready" : "Accessibility needed for live actions",
                    granted: model.accessibility, pane: "Privacy_Accessibility")
                permissionRow(
                    model.inputMonitoring ? "Input Monitoring granted" : "Input Monitoring not granted",
                    granted: model.inputMonitoring, pane: "Privacy_ListenEvent")
            } header: {
                Text("Permissions")
            } footer: {
                Text(
                    "Grant permissions to MX Forward Agent (inside MX Forward.app → Contents → Library → LoginItems). Shortcut recording may also need Accessibility for MX Forward. Closing this window quits the settings UI; the lightweight agent keeps mappings active."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
            Section("Logitech Options+") {
                Label(
                    model.logitechRunning
                        ? "Logitech’s background agent is running. Stop it before enabling."
                        : "Logitech’s background agent is stopped.",
                    systemImage: model.logitechRunning ? "exclamationmark.circle" : "checkmark.circle"
                )
                .foregroundStyle(model.logitechRunning ? Color.orange : Color.secondary)
                Text("./scripts/logitech-session.sh stop · start · status")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Section("Background agent") {
                Text(
                    "The agent starts at login and restarts after a crash. Pause restores native controls without stopping the agent."
                )
                .font(.caption).foregroundStyle(.secondary)
                Button("Start or reconnect agent") { model.reconnectAgent() }
                Button("Stop agent and disable startup", role: .destructive) {
                    Task { await model.uninstallAgent() }
                }
                .disabled(!model.agentAvailable || model.busy)
            }
            Section("Testing") {
                Toggle("Test mode — show actions without sending them", isOn: $model.preferences.testMode)
                    .disabled(!model.agentAvailable || model.busy || model.needsRelease)
                HStack {
                    Text("Check that apps receive native zoom gestures.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open zoom verification") { model.showZoomTest() }
                }
            }
            Section("Diagnostics") {
                ScrollView {
                    Text(
                        model.log.isEmpty
                            ? "Discover the mouse to begin." : model.log.suffix(30).joined(separator: "\n")
                    )
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }

    private func permissionRow(_ title: String, granted: Bool, pane: String) -> some View {
        HStack {
            Label(title, systemImage: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? Color.green : Color.primary)
            Spacer()
            Button("Open Settings") { model.openPermission(pane) }
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
    private var gesture = ButtonGesture()
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
        _ = gesture.cancel()
        timer?.invalidate()
        gesture.down(at: ProcessInfo.processInfo.systemUptime, options: .init(holdDelay: delay / 1000))
        onResult("Pressed…")
        let next = Timer(timeInterval: delay / 1000, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let event = self.gesture.advance(to: ProcessInfo.processInfo.systemUptime) {
                self.show([event])
            }
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }
    override func mouseUp(with event: NSEvent) {
        timer?.invalidate()
        timer = nil
        show(gesture.up(at: ProcessInfo.processInfo.systemUptime))
    }
    private func show(_ events: [ButtonGesture.Event]) {
        switch events.first {
        case .action(.click): onResult("Click detected")
        case .action(.hold): onResult("Hold detected · the click won’t fire")
        default: break
        }
    }
    override func viewDidMoveToWindow() {
        if window == nil {
            timer?.invalidate()
            _ = gesture.cancel()
        }
    }
}
