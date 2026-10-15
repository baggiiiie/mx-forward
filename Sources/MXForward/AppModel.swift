import AppKit
import Combine
import ForwardCore
import IOKit.hid

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences = Preferences.load() {
        didSet {
            preferences.save()
            cancelPress()
        }
    }
    @Published var diagnostics = false
    @Published var testResult = "Hold the test pad to try the timing. No actions are sent."
    @Published var status = "Ready to discover your mouse"
    @Published var lastAction = "No button activity yet"
    @Published private(set) var log: [String] = []
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var inputMonitoring =
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    @Published private(set) var logitechRunning = false
    @Published private(set) var needsRelease = false
    private let mouse = BoltMouse()
    private var interpreter = PressInterpreter()
    private var operationEpoch = 0
    private var holdTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var wakeObservers: [NSObjectProtocol] = []

    init() {
        mouse.onStatus = { [weak self] text in
            guard let self else { return }
            self.status = text
            self.connected = self.mouse.connection != nil
        }
        mouse.onLog = { [weak self] in self?.append($0) }
        mouse.onPress = { [weak self] in self?.physicalPress($0) }
        mouse.onDisconnect = { [weak self] in
            self?.operationEpoch += 1
            self?.cancelPress()
            self?.enabled = false
            self?.needsRelease = false
            self?.append("Disconnected; enable again after reconnect")
        }
        let notifications = NSWorkspace.shared.notificationCenter
        wakeObservers.append(
            notifications.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.operationEpoch += 1
                    self.cancelPress()
                    self.enabled = false
                    self.needsRelease = !self.mouse.releaseImmediately()
                    self.status = "Paused for sleep. Discover and enable again after waking."
                }
            })
        wakeObservers.append(
            notifications.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.mouse.forgetConnection()
                    self.connected = self.mouse.connection != nil
                }
            })
        refreshPermissions()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self else { return }
                self.refreshPermissions()
                await self.checkMouse()
            }
        }
    }

    private func checkMouse() async {
        guard enabled, !busy else { return }
        if logitechRunning || (!preferences.testMode && !accessibility) {
            let reason =
                logitechRunning
                ? "Paused: Logitech's agent started" : "Paused: Accessibility permission is missing"
            await pause(reason: reason)
            return
        }

        let epoch = operationEpoch
        do {
            let valid = try await mouse.verifyClaim()
            guard enabled, !busy, epoch == operationEpoch else { return }
            if !valid {
                await pause(
                    reason: "Forward control was reset. Discover and enable again.", forgetConnection: true)
            }
        } catch {
            guard enabled, !busy, epoch == operationEpoch else { return }
            append(error.localizedDescription)
            await pause(
                reason: "Mouse stopped responding. Reconnect and Discover again.", forgetConnection: true)
        }
    }

    private func append(_ text: String) {
        log.append("\(Date().formatted(date: .omitted, time: .standard))  \(text)")
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    private func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        logitechRunning = NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.logi.cp-dev-mgr"
                || $0.executableURL?.lastPathComponent == "logioptionsplus_agent"
        }
    }

    func discover() {
        guard !enabled, !busy, !needsRelease else { return }
        do {
            mouse.forgetConnection()
            connected = false
            try mouse.start()
            status = "Looking for your MX Master 3S…"
        } catch {
            status = error.localizedDescription
            append(status)
        }
    }

    func enable() async {
        guard !busy, !enabled, !needsRelease else { return }
        refreshPermissions()
        guard !logitechRunning else {
            status = "Stop Logitech's background agent before enabling."
            return
        }
        guard preferences.testMode || (accessibility && preferences.shortcut != nil) else {
            status = "Record a hold shortcut and grant Accessibility before live use."
            return
        }
        busy = true
        defer {
            busy = false
            needsRelease = mouse.claimed && !enabled
        }
        operationEpoch += 1
        let epoch = operationEpoch
        do {
            try await mouse.claim()
            guard epoch == operationEpoch else {
                try await mouse.release()
                return
            }
            enabled = true
            status =
                preferences.testMode
                ? "Test mode active · no actions will be sent"
                : "Active · click Forward, hold for your shortcut"
            append(status)
        } catch {
            if epoch == operationEpoch { status = error.localizedDescription }
            append(error.localizedDescription)
        }
    }

    func pause(reason: String = "Paused · Forward returned to the mouse", forgetConnection: Bool = false)
        async
    {
        guard !busy else { return }
        operationEpoch += 1
        let epoch = operationEpoch
        cancelPress()
        enabled = false
        busy = true
        defer {
            busy = false
            needsRelease = mouse.claimed
        }
        do {
            try await mouse.release()
            guard epoch == operationEpoch else { return }
            if forgetConnection {
                mouse.forgetConnection()
                connected = false
            }
            status = reason
            append(status)
        } catch {
            if epoch == operationEpoch {
                status = "Could not restore Forward. Retry Pause, or power-cycle the mouse."
            }
            append(error.localizedDescription)
        }
    }

    private func cancelPress() {
        holdTask?.cancel()
        holdTask = nil
        interpreter.cancel()
    }

    private func physicalPress(_ down: Bool) {
        guard enabled else { return }
        guard down != interpreter.isPressed else { return }
        if down {
            interpreter.down(
                at: ProcessInfo.processInfo.systemUptime,
                threshold: preferences.holdMilliseconds / 1000)
            lastAction = "Forward pressed…"
            let delay = preferences.holdMilliseconds
            holdTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(delay)) } catch { return }
                guard let self, self.enabled else { return }
                if let action = self.interpreter.advance(to: ProcessInfo.processInfo.systemUptime) {
                    self.perform(action)
                }
            }
        } else {
            holdTask?.cancel()
            holdTask = nil
            if let action = interpreter.up(at: ProcessInfo.processInfo.systemUptime) { perform(action) }
        }
    }

    private func perform(_ action: PressInterpreter.Action) {
        let label =
            action == .forward
            ? "Click → Forward (⌘])" : "Hold → \(preferences.shortcut?.label ?? "shortcut not set")"
        lastAction = (preferences.testMode ? "Test: " : "") + label
        append(lastAction)
        guard !preferences.testMode else { return }
        guard let shortcut = action == .forward ? KeyboardOutput.forward : preferences.shortcut,
            KeyboardOutput.send(shortcut)
        else {
            status = "Shortcut could not be sent. Check Accessibility."
            return
        }
    }

    func openPermission(_ kind: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind)") {
            NSWorkspace.shared.open(url)
        }
    }

    func quitSafely() async -> Bool {
        await pause()
        if !mouse.claimed { return true }
        let alert = NSAlert()
        alert.messageText = "Forward could not be restored"
        alert.informativeText =
            "The mouse is not responding. You can stay and retry Pause, or quit and turn the mouse off and on to restore its native Forward button."
        alert.addButton(withTitle: "Stay and retry")
        alert.addButton(withTitle: "Quit anyway")
        return alert.runModal() == .alertSecondButtonReturn
    }
}
