import AppKit
import MouseEngine
import SwiftUI

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut?
    var accessibilityLabel = "Hold keyboard shortcut"
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> RecorderButton {
        RecorderButton()
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onRecord = { shortcut = $0 }
        view.onRecordingChanged = onRecordingChanged
        view.isEnabled = context.environment.isEnabled
        view.idleTitle = shortcut?.label ?? "Record shortcut…"
        view.updateTitle()
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

struct ModifierRecorder: NSViewRepresentable {
    @Binding var modifiers: UInt64?
    var accessibilityLabel: String
    var onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let view = RecorderButton()
        view.modifiersOnly = true
        return view
    }

    func updateNSView(_ view: RecorderButton, context: Context) {
        view.onModifiersRecord = { modifiers = $0 }
        view.onRecordingChanged = onRecordingChanged
        view.isEnabled = context.environment.isEnabled
        view.idleTitle = modifiers.map(KeyboardModifiers.label) ?? "Record modifiers…"
        view.updateTitle()
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

final class RecorderButton: NSButton {
    private var recording = false
    private var pendingModifiers: UInt64 = 0
    private var windowObserver: NSObjectProtocol?
    private var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    var idleTitle = "Record shortcut…"
    var modifiersOnly = false
    var onRecord: (Shortcut) -> Void = { _ in }
    var onModifiersRecord: (UInt64) -> Void = { _ in }
    var onRecordingChanged: (Bool) -> Void = { _ in }
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
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
        pendingModifiers = 0
        if let keyTap { CFMachPortInvalidate(keyTap) }
        if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
        keyTap = nil
        keyTapSource = nil
        onRecordingChanged(false)
        updateTitle()
    }

    private func startKeyCapture() {
        // Capture system shortcuts only while this window is active.
        guard AXIsProcessTrusted(),
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue)
                    | (modifiersOnly ? CGEventMask(1 << CGEventType.flagsChanged.rawValue) : 0),
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
        if recording && modifiersOnly {
            title =
                pendingModifiers == 0
                ? "Hold modifiers… (Esc cancels)"
                : KeyboardModifiers.label(pendingModifiers) + " (release to save)"
        } else {
            title = recording ? "Press shortcut… (Esc cancels)" : idleTitle
        }
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

    override func flagsChanged(with event: NSEvent) {
        guard recording, isEnabled, modifiersOnly else { return super.flagsChanged(with: event) }
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        if modifiersOnly && event.type == .flagsChanged {
            let flags = UInt64(event.modifierFlags.rawValue) & KeyboardModifiers.mask.rawValue
            if flags == 0 && pendingModifiers != 0 {
                let modifiers = pendingModifiers
                stopRecording()
                onModifiersRecord(modifiers)
            } else {
                pendingModifiers |= flags
                updateTitle()
            }
            return
        }
        guard event.type == .keyDown, !event.isARepeat else { return }
        if event.keyCode == 53
            && (modifiersOnly
                || event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty)
        {
            stopRecording()
            return
        }
        guard !modifiersOnly else { return }
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
