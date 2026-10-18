import AppKit
import MouseEngine
import SettingsClient
import SwiftUI
import UniformTypeIdentifiers

final class ConfigEditorState: ObservableObject {
    @Published var draft = ""
    @Published var baseline = ""
    @Published var error: String?
    @Published var notice: String?
    var dirty: Bool { draft != baseline }
}

struct ConfigEditorView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var state: ConfigEditorState

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "curlybraces").foregroundStyle(.secondary)
                    Text((model.configURL.path as NSString).abbreviatingWithTildeInPath)
                        .font(.callout.monospaced()).foregroundStyle(.secondary)
                        .textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Open in Editor") { NSWorkspace.shared.open(model.configURL) }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([model.configURL])
                    } label: {
                        Image(systemName: "folder")
                    }.help("Show in Finder")
                    Menu("More") {
                        Button("Import…", action: importFile)
                        Button("Export…", action: exportFile)
                    }
                    .fixedSize()
                }
                JSONTextView(text: $state.draft)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(state.error == nil ? Color.primary.opacity(0.12) : Color.red.opacity(0.7))
                    )
                if let fileError = model.configError {
                    HStack(alignment: .firstTextBaseline) {
                        Label(
                            "The config file has an error: \(fileError)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Replace with current settings") { model.rewriteConfigFile() }
                    }
                    .font(.callout)
                }
                HStack(alignment: .firstTextBaseline) {
                    if let error = state.error {
                        Label(error, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if state.dirty {
                        Label("Unapplied changes", systemImage: "pencil").foregroundStyle(.secondary)
                    } else if let notice = state.notice {
                        Label(notice, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("In sync with your settings", systemImage: "checkmark.circle").foregroundStyle(
                            .secondary)
                    }
                    Spacer()
                    Button("Revert") { reload() }.disabled(!state.dirty)
                    Button("Apply") { apply(state.draft) }
                        .keyboardShortcut("s", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(!state.dirty)
                }
                .font(.callout)
            }
            .padding(16)
            Divider()
            ConfigReference().frame(width: 270)
        }
        .onAppear { if !state.dirty { reload(keepNotice: true) } }
        .onChange(of: model.preferences) { _, _ in
            if !state.dirty { reload(keepNotice: true) }
        }
    }

    private func reload(keepNotice: Bool = false) {
        let text = ConfigJSON.encode(model.preferences)
        state.draft = text
        state.baseline = text
        state.error = nil
        if !keepNotice { state.notice = nil }
    }

    private func apply(_ text: String) {
        do {
            try model.applyConfig(text)
            reload()
            state.notice = "Applied"
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            state.draft = text
            apply(text)
        } catch {
            state.error = error.localizedDescription
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "mx-forward.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigJSON.encode(model.preferences).write(to: url, atomically: true, encoding: .utf8)
            state.notice = "Exported to \(url.lastPathComponent)"
        } catch {
            state.error = error.localizedDescription
        }
    }
}

private struct ConfigReference: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Reference").font(.headline)
                entry("Buttons", "forward  back  gesture  top\nwheelButton")
                entry("Each button", "click  hold  up  down  left  right")
                entry(
                    "Actions",
                    """
                    "cmd+shift+t"  a shortcut
                    "none"  "default"
                    "missionControl"  "appExpose"
                    "desktopLeft"  "desktopRight"
                    "smartZoom"  "middleClick"
                    "zoom"  up and down only
                    "scroll"  all four drag directions together (trackpad-style scrolling)
                    """)
                entry("Modifiers", "cmd  opt  ctrl  shift  fn\nSymbols also work: \"⌘⇧T\"")
                entry(
                    "Keys",
                    "a–z  0–9  - = [ ] ; ' , . / \\ `\nreturn tab space delete escape\nleft right up down home end\npageup pagedown f1–f20"
                )
                entry("wheel.mode", "unchanged  ratchet  freeSpin")
                entry("thumbWheel.direction", "unchanged  standard  reversed")
                entry(
                    "Percentages",
                    "speedPercent, accelerationPercent, dragSensitivityPercent, zoomSpeedPercent use 100 = 100%."
                )
                Text(
                    "Any key can be left out to keep its current value. Edits saved to the file from another editor apply within a second. Key names use US-layout positions."
                )
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .background(Color.primary.opacity(0.025))
    }

    private func entry(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A plain-text editor. Smart quotes and other substitutions are off because they break JSON.
struct JSONTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.setAccessibilityLabel("JSON configuration")
        textView.delegate = context.coordinator
        textView.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        let selection = textView.selectedRanges
        textView.string = text
        if (selection.last?.rangeValue.upperBound ?? 0) <= (text as NSString).length {
            textView.selectedRanges = selection
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
