import MouseEngine
import AppKit
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var accessibilityLabel = "Hold keyboard shortcut"
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.bezelStyle = .rounded
        return view
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onRecord = { shortcut = $0 }
        view.onRecordingChanged = onRecordingChanged
        view.isEnabled = context.environment.isEnabled
        view.shortcutTitle = shortcut?.label ?? "Record shortcut…"
        view.updateTitle()
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

final class RecorderButton: NSButton {
    private var recording = false
    private var windowObserver: NSObjectProtocol?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    var shortcutTitle = "Record shortcut…"
    var onRecord: (Shortcut) -> Void = { _ in }
    var onRecordingChanged: (Bool) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(beginRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit {
        if let keyTap { CFMachPortInvalidate(keyTap) }
        if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
    }

    @objc func beginRecording() {
        guard isEnabled, !recording else { return }
        window?.makeFirstResponder(self)
        recording = true
        onRecordingChanged(true)
        startKeyCapture()
        updateTitle()
    }

    private func stopRecording() {
        guard recording else { return }
        recording = false
        if let keyTap { CFMachPortInvalidate(keyTap) }
        if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
        keyTap = nil
        keyTapSource = nil
        onRecordingChanged(false)
        updateTitle()
    }

    private func startKeyCapture() {
        // Catch system shortcuts before macOS handles them, only while recording in this window.
        guard AXIsProcessTrusted(),
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    return MainActor.assumeIsolated {
                        let recorder = Unmanaged<RecorderButton>.fromOpaque(context).takeUnretainedValue()
                        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                            if let tap = recorder.keyTap { CGEvent.tapEnable(tap: tap, enable: true) }
                            return Unmanaged.passUnretained(event)
                        }
                        guard recorder.recording, recorder.window?.isKeyWindow == true, NSApp.isActive,
                            let key = NSEvent(cgEvent: event)
                        else { return Unmanaged.passUnretained(event) }
                        recorder.capture(key)
                        return nil
                    }
                }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        keyTap = tap
        keyTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let keyTapSource { CFRunLoopAddSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
    }

    func updateTitle() {
        if !isEnabled { stopRecording() }
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
        guard event.type == .keyDown, !event.isARepeat else { return }
        if event.keyCode == 53
            && event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        {
            stopRecording()
            return
        }
        stopRecording()
        onRecord(Shortcut.recorded(from: event))
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { stopRecording() }
        return resigned
    }

    override func viewDidMoveToWindow() {
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
        stopRecording()
        if let window {
            windowObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.stopRecording() }
        }
    }
}
