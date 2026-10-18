import AgentSupport
import AppKit
import Combine
import ForwardCore
import MouseEngine

/// The settings UI talks to the agent; it never opens the receiver.
@MainActor
package final class SettingsModel: ObservableObject {
    @Published package var preferences = Preferences() {
        didSet {
            guard !applyingState, oldValue != preferences else { return }
            if editBase == nil { editBase = oldValue }
            editGeneration += 1
            settingsDirty = true
            settingsTask?.cancel()
            settingsTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                self?.flushSettings()
            }
        }
    }
    @Published package var testResult = "Hold the test pad to try the timing. No actions are sent."
    @Published package private(set) var status = "Connecting to the mouse agent…"
    @Published package private(set) var lastAction = "No button activity yet"
    @Published package private(set) var log: [String] = []
    @Published package private(set) var enabled = false
    @Published package private(set) var busy = false
    @Published package private(set) var connected = false
    @Published package private(set) var accessibility = false
    @Published package private(set) var inputMonitoring = false
    @Published package private(set) var logitechRunning = false
    @Published package private(set) var needsRelease = false
    @Published package private(set) var heldControls = Set<MouseControl>()
    @Published package private(set) var configError: String?
    @Published package private(set) var agentAvailable = false
    @Published package private(set) var settingsDirty = false
    package let configURL = ConfigJSON.defaultURL
    package var canEnable: Bool { agentAvailable && remoteCanEnable && !settingsDirty }

    private let client: AgentConnection
    private var applyingState = false
    private var remoteCanEnable = false
    private var editBase: Preferences?
    private var editGeneration = 0
    private var saveError: String?
    private var recording = false
    private var closing = false
    private var pollTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var zoomTestWindow: ZoomTestWindow?

    private struct Work {
        var request: AgentRequest
        var savesSettings = false
        var completion: CheckedContinuation<Bool, Never>?
    }
    private var queue: [Work] = []

    package init(client: AgentConnection? = nil, installService: Bool = true) {
        self.client = client ?? AgentConnection()
        startPolling(installService: installService)
    }

    package func reconnectAgent() {
        client.close()
        closing = false
        startPolling(installService: true)
    }

    private func startPolling(installService: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if installService {
                do { try await AgentService.installAndStart(appURL: Bundle.main.bundleURL) } catch {
                    self?.status = error.localizedDescription
                    return
                }
            }
            while !Task.isCancelled {
                guard let self, !self.closing else { return }
                if self.worker == nil && self.queue.isEmpty {
                    let request =
                        self.recording ? AgentRequest(.recording, recording: true) : AgentRequest(.snapshot)
                    self.enqueue(Work(request: request))
                }
                do {
                    try await Task.sleep(for: self.agentAvailable ? .milliseconds(200) : .seconds(2))
                } catch {
                    return
                }
            }
        }
    }

    private func flushSettings() {
        guard settingsDirty, !queue.contains(where: \.savesSettings) else { return }
        enqueue(Work(request: AgentRequest(.settings), savesSettings: true))
    }

    private func enqueue(_ work: Work) {
        queue.append(work)
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !self.queue.isEmpty {
                var work = self.queue.removeFirst()
                if work.savesSettings && !self.settingsDirty { continue }
                let generation = self.editGeneration
                if work.savesSettings {
                    work.request = AgentRequest(
                        .settings, preferences: self.preferences, basePreferences: self.editBase)
                }
                var succeeded = false
                do {
                    let response = try await self.client.exchange(work.request)
                    let available = response.state != nil
                    if self.agentAvailable != available { self.agentAvailable = available }
                    succeeded = response.error == nil && available
                    if work.savesSettings && succeeded, let sent = work.request.preferences,
                        let state = response.state
                    {
                        self.saved(sent, generation: generation, state: state.preferences)
                    }
                    if let state = response.state { self.apply(state) }
                    if let error = response.error { self.report(error, saving: work.savesSettings) }
                    if succeeded && self.settingsDirty && !work.savesSettings && !self.closing {
                        self.flushSettings()
                    }
                } catch {
                    self.agentAvailable = false
                    self.enabled = false
                    self.heldControls = []
                    self.report(
                        "Mouse agent unavailable: \(error.localizedDescription)", saving: work.savesSettings)
                }
                work.completion?.resume(returning: succeeded)
            }
            self.worker = nil
        }
    }

    private func saved(_ sent: Preferences, generation: Int, state: Preferences) {
        saveError = nil
        if generation == editGeneration {
            settingsDirty = false
            editBase = nil
        } else {
            // Keep edits made while the previous save was in flight, including Undo.
            applyingState = true
            preferences = state.applyingEdits(from: sent, to: preferences)
            applyingState = false
            settingsDirty = preferences != state
            editBase = settingsDirty ? state : nil
            if settingsDirty { flushSettings() }
        }
    }

    private func report(_ message: String, saving: Bool) {
        if saving { saveError = "Could not save settings: \(message)" }
        status = saveError ?? message
    }

    private func apply(_ state: AgentState) {
        if !settingsDirty {
            applyingState = true
            if preferences != state.preferences { preferences = state.preferences }
            applyingState = false
        }
        let message = saveError ?? state.status
        if status != message { status = message }
        if lastAction != state.lastAction { lastAction = state.lastAction }
        if log != state.log { log = state.log }
        if enabled != state.enabled { enabled = state.enabled }
        if busy != state.busy { busy = state.busy }
        if connected != state.connected { connected = state.connected }
        if accessibility != state.accessibility { accessibility = state.accessibility }
        if inputMonitoring != state.inputMonitoring { inputMonitoring = state.inputMonitoring }
        if logitechRunning != state.logitechRunning { logitechRunning = state.logitechRunning }
        if needsRelease != state.needsRelease { needsRelease = state.needsRelease }
        if configError != state.configError { configError = state.configError }
        let held = Set(state.held.compactMap(MouseControl.init(rawValue:)))
        if heldControls != held { heldControls = held }
        remoteCanEnable = state.canEnable
    }

    @discardableResult
    private func command(_ request: AgentRequest) async -> Bool {
        settingsTask?.cancel()
        flushSettings()
        return await withCheckedContinuation { enqueue(Work(request: request, completion: $0)) }
    }

    package func enable() async { await command(.init(.enable)) }
    package func pause() async { await command(.init(.pause)) }
    package func discover() { enqueue(Work(request: .init(.discover))) }
    package func rewriteConfigFile() { enqueue(Work(request: .init(.rewriteConfig))) }
    package func setRecordingShortcut(_ recording: Bool) {
        self.recording = recording
        enqueue(Work(request: .init(.recording, recording: recording)))
    }

    package func applyConfig(_ text: String) throws {
        preferences = try ConfigJSON.apply(text, to: preferences)
        settingsTask?.cancel()
        flushSettings()
    }

    /// Don't exit with unsaved edits. Disconnecting also ends shortcut recording.
    package func finish() async -> Bool {
        closing = true
        pollTask?.cancel()
        settingsTask?.cancel()
        if settingsDirty { await command(.init(.snapshot)) }
        guard !settingsDirty else {
            closing = false
            startPolling(installService: false)
            return false
        }
        for work in queue { work.completion?.resume(returning: false) }
        queue.removeAll()
        client.close()
        return true
    }

    package func uninstallAgent() async {
        guard await finish() else { return }
        do {
            try await AgentService.uninstall()
            agentAvailable = false
            enabled = false
            status = "Agent stopped; startup disabled."
        } catch {
            status = error.localizedDescription
            closing = false
            startPolling(installService: false)
        }
    }

    package func showZoomTest() {
        if zoomTestWindow == nil {
            zoomTestWindow = ZoomTestWindow { [weak self] text in self?.lastAction = text }
        }
        zoomTestWindow?.showWindow(nil)
        zoomTestWindow?.window?.makeKeyAndOrderFront(nil)
    }

    package func openPermission(_ kind: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind)") {
            NSWorkspace.shared.open(url)
        }
    }
}
