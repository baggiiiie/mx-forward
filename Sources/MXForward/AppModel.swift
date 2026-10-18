import AppKit
import Combine
import ForwardCore
import MouseEngine
import AgentSupport

/// Presentation-only proxy. This process never opens the receiver or owns mappings.
@MainActor
final class AppModel: ObservableObject {
    @Published var preferences = Preferences() {
        didSet {
            guard !applyingState, oldValue != preferences else { return }
            editGeneration += 1
            settingsDirty = true
            scheduleSettings()
        }
    }
    @Published var diagnostics = false
    @Published var testResult = "Hold the test pad to try the timing. No actions are sent."
    @Published var status = "Connecting to the mouse agent…"
    @Published var lastAction = "No button activity yet"
    @Published private(set) var log: [String] = []
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var connected = false
    @Published private(set) var accessibility = false
    @Published private(set) var inputMonitoring = false
    @Published private(set) var logitechRunning = false
    @Published private(set) var needsRelease = false
    @Published private(set) var heldControls = Set<MouseControl>()
    @Published private(set) var configError: String?
    @Published private(set) var agentAvailable = false
    let configURL: URL? = ConfigJSON.defaultURL
    var canEnable: Bool { agentAvailable && remoteCanEnable && !settingsDirty }

    private let client: AgentConnection
    var settingsPending: Bool { settingsDirty }
    private var applyingState = false
    private var remoteCanEnable = false
    @Published private var settingsDirty = false
    private var editGeneration = 0
    private var pollTask: Task<Void, Never>?
    private var settingsTask: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var zoomTestWindow: ZoomTestWindow?
    private var closing = false
    private struct Work {
        var request: AgentRequest
        var generation: Int?
        var completion: CheckedContinuation<Void, Never>?
    }
    private var queue: [Work] = []

    init(client: AgentConnection? = nil, installService: Bool = true) {
        self.client = client ?? AgentConnection()
        startPolling(installService: installService)
    }

    func reconnectAgent() {
        client.close()
        closing = false
        startPolling(installService: true)
    }

    private func startPolling(installService: Bool) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            if installService {
                do { try await AgentService.installAndStart(appURL: Bundle.main.bundleURL) }
                catch { self?.status = error.localizedDescription; return }
            }
            while !Task.isCancelled {
                guard let self, !self.closing else { return }
                if self.worker == nil && self.queue.isEmpty {
                    self.enqueue(.init(.snapshot))
                }
                do { try await Task.sleep(for: self.agentAvailable ? .milliseconds(200) : .seconds(2)) }
                catch { return }
            }
        }
    }

    private func scheduleSettings() {
        settingsTask?.cancel()
        settingsTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
            self?.flushSettings()
        }
    }

    private func flushSettings() {
        guard settingsDirty else { return }
        // Coalesce slider changes that haven't gone over XPC yet.
        queue.removeAll { $0.generation != nil }
        enqueue(.init(.settings, preferences: preferences), generation: editGeneration)
    }

    private func enqueue(_ request: AgentRequest, generation: Int? = nil,
                         completion: CheckedContinuation<Void, Never>? = nil) {
        queue.append(Work(request: request, generation: generation, completion: completion))
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while !self.queue.isEmpty {
                let work = self.queue.removeFirst()
                do {
                    let response = try await self.client.exchange(work.request)
                    if !self.agentAvailable { self.agentAvailable = true }
                    if work.generation == self.editGeneration && response.error == nil {
                        self.settingsDirty = false
                    }
                    if let state = response.state { self.apply(state) }
                    if let error = response.error { self.status = error }
                    if work.request.command == .snapshot && self.settingsDirty { self.flushSettings() }
                } catch {
                    self.agentAvailable = false
                    self.enabled = false
                    self.heldControls = []
                    self.status = "Mouse agent unavailable: \(error.localizedDescription)"
                }
                work.completion?.resume()
            }
            self.worker = nil
        }
    }

    private func apply(_ state: AgentState) {
        if !settingsDirty {
            applyingState = true
            if preferences != state.preferences { preferences = state.preferences }
            applyingState = false
        }
        if status != state.status { status = state.status }
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

    private func command(_ request: AgentRequest) async {
        settingsTask?.cancel()
        flushSettings()
        await withCheckedContinuation { enqueue(request, completion: $0) }
    }

    func enable() async { await command(.init(.enable)) }
    func pause() async { await command(.init(.pause)) }
    func discover() { enqueue(.init(.discover)) }
    func rewriteConfigFile() { enqueue(.init(.rewriteConfig)) }
    func setRecordingShortcut(_ recording: Bool) { enqueue(.init(.recording, recording: recording)) }

    func applyConfig(_ text: String) throws {
        preferences = try ConfigJSON.apply(text, to: preferences)
        settingsTask?.cancel()
        flushSettings()
    }

    /// Flush settings and release only this UI's recording lease; leave mappings active.
    func finish() async {
        closing = true
        pollTask?.cancel()
        settingsTask?.cancel()
        await command(.init(.recording, recording: false))
        client.close()
    }

    func uninstallAgent() async {
        await pause()
        do {
            try await AgentService.uninstall()
            agentAvailable = false
            status = "Agent stopped; startup disabled. Reopen MX Forward to install it again."
            closing = true
            pollTask?.cancel()
            client.close()
        } catch { status = error.localizedDescription }
    }

    func showZoomTest() {
        if zoomTestWindow == nil { zoomTestWindow = ZoomTestWindow { [weak self] text in self?.lastAction = text } }
        zoomTestWindow?.showWindow(nil)
        zoomTestWindow?.window?.makeKeyAndOrderFront(nil)
    }

    func openPermission(_ kind: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind)") {
            NSWorkspace.shared.open(url)
        }
    }
}
