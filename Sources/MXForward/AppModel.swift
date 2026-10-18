import AppKit
import Combine
import ForwardCore
import IOKit.hid

@MainActor
final class AppModel: ObservableObject {
    @Published var preferences = Preferences.load() {
        didSet {
            settingsChanged(from: oldValue)
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
    @Published private(set) var heldControls = Set<MouseControl>()
    @Published private(set) var configError: String?
    let configURL: URL?
    private var configModified: Date?
    private var configTask: Task<Void, Never>?
    private let mouse: BoltMouse
    private var wheel = WheelInterpreter()
    /// Gestures for buttons that are currently held.
    private var gestures: [MouseControl: ButtonGesture] = [:]
    private var holdTasks: [MouseControl: Task<Void, Never>] = [:]
    private var actionAnchors: [MouseControl: CGPoint] = [:]
    private var dragPointer: PointerOutput?
    #if !MX_HEADLESS
    private var zoomTestWindow: ZoomTestWindow?
    #endif
    private let startsHardware: Bool
    private let persistsSettings: Bool
    private var appliedConfiguration: MouseConfiguration?
    private var settingsTask: Task<Void, Never>?
    private var recordingShortcut = false
    private var suppressedControls = Set<MouseControl>()

    var canEnable: Bool {
        connected && !enabled && !busy && !sleeping && !quitting && !needsRelease
            && !logitechRunning && preferences.hasMappings
            && (preferences.testMode || accessibility)
    }
    private var operationEpoch = 0
    private var sleeping = false
    private var quitting = false
    private var monitorTask: Task<Void, Never>?
    private var wakeObservers: [NSObjectProtocol] = []

    init(
        mouse device: BoltMouse? = nil, configURL: URL? = nil,
        initialPreferences: Preferences? = nil, startsHardware: Bool = true,
        persistsSettings: Bool = true
    ) {
        self.mouse = device ?? BoltMouse()
        self.configURL = configURL
        self.startsHardware = startsHardware
        self.persistsSettings = persistsSettings
        if let initialPreferences { self.preferences = initialPreferences }
        mouse.onStatus = { [weak self] text in
            guard let self else { return }
            self.status = text
            self.connected = self.mouse.connection != nil
        }
        mouse.onLog = { [weak self] in self?.append($0) }
        mouse.onPress = { [weak self] control, down in self?.physicalPress(control, down: down) }
        mouse.onMovement = { [weak self] dx, dy in
            guard let self, self.enabled, !self.recordingShortcut,
                let control = self.gestures.keys.first(where: self.reportsMovement)
            else { return }
            self.perform(self.gestures[control]?.move(dx: dx, dy: dy) ?? [], from: control)
        }
        mouse.onScroll = { [weak self] scroll, multiplier in
            guard let self, self.enabled, self.preferences.wheelEnabled else { return }
            let pixels = self.wheel.pixels(
                for: scroll, multiplier: multiplier, speed: self.preferences.wheelSpeed,
                natural: self.preferences.wheelNatural,
                acceleration: self.preferences.wheelAcceleration, at: ProcessInfo.processInfo.systemUptime)
            guard pixels != 0 else { return }
            let label =
                (self.preferences.testMode ? "Test: " : "") + "Main wheel → \(pixels > 0 ? "up" : "down")"
            if self.lastAction != label { self.lastAction = label }
            if !self.preferences.testMode && !WheelOutput.send(pixels: pixels) {
                self.status = "Scrolling could not be sent. Check Accessibility."
            }
        }
        mouse.onDisconnect = { [weak self] in
            self?.operationEpoch += 1
            self?.cancelInput()
            self?.enabled = false
            self?.appliedConfiguration = nil
            self?.needsRelease = false
            self?.append("Disconnected; waiting for the mouse to reconnect")
        }
        let notifications = NSWorkspace.shared.notificationCenter
        wakeObservers.append(
            notifications.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = true
                    self.operationEpoch += 1
                    self.cancelInput()
                    self.enabled = false
                    self.needsRelease = !self.mouse.releaseImmediately()
                    self.status = "Paused for sleep"
                }
            })
        wakeObservers.append(
            notifications.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.sleeping = false
                    self.mouse.forgetConnection()
                    self.connected = self.mouse.connection != nil
                }
            })
        refreshPermissions()
        if configURL != nil {
            syncConfigFile()
            configTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    self?.syncConfigFile()
                }
            }
        }
        connectIfNeeded()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self else { return }
                self.refreshPermissions()
                await self.maintainConnection()
            }
        }
    }

    private func settingsChanged(from old: Preferences) {
        if persistsSettings { preferences.save() }
        writeConfigFile()
        var previous = old
        previous.resumeMappings = preferences.resumeMappings
        guard previous != preferences else { return }
        cancelInput(testMode: old.testMode)
        if preferences.resumeMappings { scheduleSettingsApply() }
    }

    private func scheduleSettingsApply() {
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            self?.settingsTask = nil
            await self?.applyCurrentSettings()
        }
    }

    private func applyCurrentSettings() async {
        guard !busy, !sleeping, !quitting, preferences.resumeMappings else { return }
        if enabled && appliedConfiguration != preferences.hardwareConfiguration {
            await suspend(reason: "Applying mouse settings…")
        }
        if !preferences.hasMappings && !needsRelease { status = "No mouse controls enabled" }
        if !enabled && canEnable { await enable() }
    }

    /// Applies JSON from the editor or an imported file, then saves the full config to disk.
    func applyConfig(_ text: String) throws {
        let next = try ConfigJSON.apply(text, to: preferences)
        if next != preferences {
            preferences = next
            append("Applied JSON configuration")
        }
        writeConfigFile(force: true)
    }

    func rewriteConfigFile() { writeConfigFile(force: true) }

    private func fileModified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func syncConfigFile() {
        guard let url = configURL else { return }
        let modified = fileModified(url)
        guard modified == nil || modified != configModified else { return }
        configModified = modified
        guard modified != nil, let text = try? String(contentsOf: url, encoding: .utf8) else {
            writeConfigFile(force: true)
            return
        }
        do {
            let next = try ConfigJSON.apply(text, to: preferences)
            configError = nil
            if next != preferences {
                preferences = next
                append("Applied changes from \(url.lastPathComponent)")
            }
        } catch {
            let message = error.localizedDescription
            if configError != message { append("\(url.lastPathComponent): \(message)") }
            configError = message
        }
    }

    private func writeConfigFile(force: Bool = false) {
        guard persistsSettings, let url = configURL else { return }
        if !force, let text = try? String(contentsOf: url, encoding: .utf8) {
            // Don't overwrite a file the user is still fixing.
            guard let current = try? ConfigJSON.apply(text, to: preferences), current != preferences
            else { return }
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ConfigJSON.encode(preferences).write(to: url, atomically: true, encoding: .utf8)
            configModified = fileModified(url)
            configError = nil
        } catch {
            configError = "Could not write \(url.path): \(error.localizedDescription)"
        }
    }

    func setRecordingShortcut(_ recording: Bool) {
        guard recordingShortcut != recording else { return }
        recordingShortcut = recording
        if recording { cancelInput() }
    }

    private func connectIfNeeded() {
        guard startsHardware, !sleeping, !quitting, !busy, !enabled, !needsRelease,
            mouse.connection == nil
        else { return }
        guard !logitechRunning else {
            status = "Waiting for Logitech's mouse agent to stop"
            return
        }
        do { try mouse.start() } catch {
            let message = error.localizedDescription
            if status != message { append(message) }
            status = message
        }
    }

    private func maintainConnection() async {
        guard !sleeping, !quitting, !busy else { return }
        if enabled {
            if appliedConfiguration != preferences.hardwareConfiguration {
                await applyCurrentSettings()
            } else {
                await checkMouse()
            }
            return
        }
        guard !logitechRunning else {
            status = "Waiting for Logitech's mouse agent to stop"
            return
        }
        if needsRelease {
            await suspend(reason: "Buttons restored", forgetConnection: true)
            return
        }
        connectIfNeeded()
        if preferences.resumeMappings && canEnable { await enable() }
    }

    private func checkMouse() async {
        guard enabled, !busy else { return }
        if logitechRunning || (!preferences.testMode && !accessibility) {
            let reason =
                logitechRunning
                ? "Paused: Logitech's agent started" : "Paused: Accessibility permission is missing"
            await suspend(reason: reason)
            return
        }

        let epoch = operationEpoch
        do {
            let valid = try await mouse.verifyClaim()
            guard enabled, !busy, epoch == operationEpoch else { return }
            if !valid {
                await suspend(reason: "Button control was reset; reconnecting…", forgetConnection: true)
            }
        } catch {
            guard enabled, !busy, epoch == operationEpoch else { return }
            append(error.localizedDescription)
            await suspend(reason: "Waiting for the mouse to reconnect", forgetConnection: true)
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
        mouse.forgetConnection()
        connected = false
        connectIfNeeded()
    }

    func enable() async {
        guard startsHardware, !busy, !enabled, !needsRelease, !sleeping, !quitting else { return }
        refreshPermissions()
        guard !logitechRunning else {
            status = "Stop Logitech's background agent before enabling."
            return
        }
        guard preferences.hasMappings, preferences.testMode || accessibility
        else {
            status =
                "Choose a mouse control and grant Accessibility for live actions."
            return
        }
        busy = true
        defer {
            busy = false
            needsRelease = mouse.claimed && !enabled
            if enabled && appliedConfiguration != preferences.hardwareConfiguration {
                scheduleSettingsApply()
            }
        }
        operationEpoch += 1
        let epoch = operationEpoch
        let configuration = preferences.hardwareConfiguration
        do {
            try await mouse.claim(
                configuration.controls, movement: configuration.movementControls,
                wheelMode: configuration.wheelMode, horizontalInverted: configuration.horizontalInverted)
            guard epoch == operationEpoch else {
                try await mouse.release()
                return
            }
            if !preferences.resumeMappings { preferences.resumeMappings = true }
            appliedConfiguration = configuration
            enabled = true
            status =
                preferences.testMode
                ? "Test mode active · mouse actions are shown"
                : "Selected mouse mappings active"
            append(status)
        } catch {
            if epoch == operationEpoch { status = error.localizedDescription }
            append(error.localizedDescription)
        }
    }

    func pause() async {
        guard !busy else { return }
        if preferences.resumeMappings { preferences.resumeMappings = false }
        await suspend(reason: "Paused · buttons returned to the mouse")
    }

    private func suspend(reason: String, forgetConnection: Bool = false) async {
        guard !busy else { return }
        operationEpoch += 1
        let epoch = operationEpoch
        cancelInput()
        enabled = false
        appliedConfiguration = nil
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
                status = "Could not restore a button. Retry Pause, or power-cycle the mouse."
            }
            append(error.localizedDescription)
        }
    }

    private func cancelInput(testMode: Bool? = nil) {
        suppressedControls.formUnion(heldControls)
        for control in Array(gestures.keys) {
            perform(gestures[control]?.cancel() ?? [], from: control, testMode: testMode)
        }
        gestures.removeAll()
        actionAnchors.removeAll()
        dragPointer = nil
        for task in holdTasks.values { task.cancel() }
        holdTasks.removeAll()
        wheel.cancel()
    }

    private func reportsMovement(_ control: MouseControl) -> Bool {
        appliedConfiguration?.movementControls.contains(control) ?? false
    }

    private func physicalPress(_ control: MouseControl, down: Bool) {
        if down != heldControls.contains(control) {
            if down { heldControls.insert(control) } else { heldControls.remove(control) }
        }
        if suppressedControls.contains(control) {
            if !down { suppressedControls.remove(control) }
            return
        }
        guard enabled, !recordingShortcut, preferences.controls.contains(control) else {
            if down { suppressedControls.insert(control) }
            return
        }
        // Every button report repeats the state of all held buttons.
        guard down != (gestures[control] != nil) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard down else {
            holdTasks.removeValue(forKey: control)?.cancel()
            let events = gestures[control]?.up(at: now) ?? []
            gestures[control] = nil
            perform(events, from: control)
            actionAnchors[control] = nil
            if preferences.buttons[control].dragScroll { dragPointer = nil }
            return
        }
        // Movement reports don't say which button is held, so two dragging buttons can't share them.
        if reportsMovement(control), let other = gestures.keys.first(where: reportsMovement) {
            holdTasks.removeValue(forKey: other)?.cancel()
            let events = gestures[other]?.cancel() ?? []
            gestures[other] = nil
            perform(events, from: other)
            actionAnchors[other] = nil
            dragPointer = nil
            suppressedControls.formUnion([control, other])
            append("Cancelled: \(other.name) and \(control.name) were held together")
            return
        }
        let mapping = preferences.buttons[control]
        let options = ButtonGesture.Options(
            holdDelay: mapping.hold.isNone ? nil : mapping.holdMilliseconds / 1000,
            dragDistance: 120 / mapping.dragSensitivity, verticalZoom: mapping.verticalZoom,
            zoomSpeed: mapping.zoomSpeed, discardFirstReport: mouse.connection?.discardFirstMovement ?? false,
            dragScroll: mapping.dragScroll, scrollSpeed: mapping.dragSensitivity)
        var gesture = ButtonGesture()
        gesture.down(at: now, options: options)
        gestures[control] = gesture
        let anchor = CGEvent(source: nil)?.location ?? .zero
        actionAnchors[control] = anchor
        if mapping.dragScroll { dragPointer = PointerOutput(at: anchor) }
        lastAction = "\(control.name) pressed…"
        if let delay = options.holdDelay {
            holdTasks[control] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.enabled,
                    let event = self.gestures[control]?.advance(to: ProcessInfo.processInfo.systemUptime)
                else { return }
                self.perform([event], from: control)
            }
        }
    }

    private func perform(_ events: [ButtonGesture.Event], from control: MouseControl, testMode: Bool? = nil) {
        let testMode = testMode ?? preferences.testMode
        for event in events {
            switch event {
            case .action(let slot): perform(slot, of: control, testMode: testMode)
            case .zoom(let zoom): perform(zoom, from: control, testMode: testMode)
            case .pointer(let dx, let dy):
                // Keep normal cursor movement in test mode too.
                if dragPointer?.send(dx: dx, dy: dy) == false {
                    status = "Pointer movement could not be sent. Check Accessibility."
                }
            case .scroll(let scroll):
                lastAction = (testMode ? "Test: " : "") + "\(control.name) drag → Scroll & navigate"
                if !testMode && !WheelOutput.sendDrag(scroll, at: actionAnchors[control] ?? .zero) {
                    status = "Scrolling could not be sent. Check Accessibility."
                }
            }
        }
    }

    private func perform(_ slot: ButtonSlot, of control: MouseControl, testMode: Bool) {
        let action = preferences.buttons[control][slot]
        lastAction = (testMode ? "Test: " : "") + "\(control.name) \(slot.rawValue) → \(action.label)"
        append(lastAction)
        guard !testMode, !action.isNone else { return }
        if !ActionOutput.send(action, at: actionAnchors[control] ?? .zero) {
            status = "\(control.name) action could not be sent. Check Accessibility."
        }
    }

    private func perform(_ zoom: ZoomAction, from control: MouseControl, testMode: Bool) {
        switch zoom {
        case .begin:
            lastAction = "\(control.name) drag → Zoom"
            append("Zoom began")
        case .magnify(let amount):
            lastAction = "\(control.name) drag \(amount > 0 ? "up → Zoom in" : "down → Zoom out")"
        case .end, .cancel: append(zoom == .end ? "Zoom ended" : "Zoom cancelled")
        case .click: break
        }
        if !testMode && !ZoomOutput.send(zoom, at: actionAnchors[control] ?? .zero) {
            status = "Zoom could not be sent. Check Accessibility."
        }
    }

    #if !MX_HEADLESS
    func showZoomTest() {
        if zoomTestWindow == nil {
            zoomTestWindow = ZoomTestWindow { [weak self] in self?.append($0) }
        }
        zoomTestWindow?.showWindow(nil)
        zoomTestWindow?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openPermission(_ kind: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind)") {
            NSWorkspace.shared.open(url)
        }
    }

    #endif

    func quitSafely(showAlert: Bool = true) async -> Bool {
        quitting = true
        defer { quitting = false }
        await suspend(reason: "Stopped · buttons returned to the mouse")
        if !mouse.claimed { return true }
        #if MX_HEADLESS
        return false
        #else
        guard showAlert else { return false }
        let alert = NSAlert()
        alert.messageText = "Mouse buttons could not be restored"
        alert.informativeText =
            "The mouse is not responding. You can stay and retry Pause, or quit and turn the mouse off and on to restore its native buttons."
        alert.addButton(withTitle: "Stay and retry")
        alert.addButton(withTitle: "Quit anyway")
        return alert.runModal() == .alertSecondButtonReturn
        #endif
    }
}
