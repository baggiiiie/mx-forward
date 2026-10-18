import AppKit
import Darwin
import MouseEngine

/// Each XPC connection owns its recording suppression lease. Losing the UI cannot
/// leave mappings permanently suppressed. No UI objects are created in this process.
package final class AgentServer: NSObject, NSXPCListenerDelegate {
    private let engine: MouseEngine
    private var peers: [UUID: (NSXPCConnection, Bool)] = [:]
    private var stopping = false
    private let listener: NSXPCListener

    @MainActor
    package init(engine: MouseEngine, listener: NSXPCListener = NSXPCListener(machServiceName: AgentIdentity.service)) {
        self.engine = engine
        self.listener = listener
        super.init()
        listener.delegate = self
    }

    package func start() { listener.resume() }

    package func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        let id = UUID()
        let peer = AgentPeer(server: self, id: id)
        connection.exportedInterface = NSXPCInterface(with: AgentProtocol.self)
        connection.exportedObject = peer
        connection.invalidationHandler = { [weak self] in
            Task { @MainActor in self?.disconnect(id) }
        }
        Task { @MainActor [weak self] in
            guard let self, !self.stopping, self.peers.count < 8 else {
                connection.invalidate()
                return
            }
            self.peers[id] = (connection, false)
            connection.resume()
        }
        return true
    }

    @MainActor
    private func disconnect(_ id: UUID) {
        peers.removeValue(forKey: id)
        engine.setRecordingShortcut(peers.values.contains { $0.1 })
    }

    @MainActor
    fileprivate func handle(_ data: Data, from id: UUID) async -> Data {
        var error: String?
        do {
            guard !stopping, peers[id] != nil else {
                throw IPCError("The mouse agent is stopping")
            }
            let request = try AgentCodec.decode(AgentRequest.self, from: data)
            guard request.version == AgentIdentity.protocolVersion else {
                throw IPCError("Agent/UI version mismatch. Restart after updating MX Forward.")
            }
            switch request.command {
            case .snapshot: break
            case .settings:
                guard var preferences = request.preferences else { throw IPCError("Missing settings") }
                // Enable/Pause belongs to the agent, never to a stale settings snapshot.
                preferences.resumeMappings = engine.preferences.resumeMappings
                engine.preferences = preferences.normalized()
            case .enable:
                guard engine.canEnable else { throw IPCError("Cannot enable: \(engine.status)") }
                await engine.enable()
            case .pause:
                guard !engine.busy else { throw IPCError("Mouse operation in progress; retry Pause") }
                await engine.pause()
            case .discover: engine.discover()
            case .rewriteConfig: engine.rewriteConfigFile()
            case .recording:
                peers[id]?.1 = request.recording ?? false
                engine.setRecordingShortcut(peers.values.contains { $0.1 })
            }
        } catch let caught { error = caught.localizedDescription }
        // All replies include the authoritative state, including errors.
        return (try? JSONEncoder().encode(AgentResponse(state: AgentState(engine), error: error))) ?? Data()
    }

    @MainActor
    package func stop() async -> Bool {
        guard !stopping else { return false }
        stopping = true
        listener.suspend()
        let restored = await engine.shutdown()
        for (connection, _) in peers.values { connection.invalidate() }
        peers.removeAll()
        return restored
    }
}

private final class AgentPeer: NSObject, AgentProtocol {
    private weak var server: AgentServer?
    private let id: UUID

    init(server: AgentServer, id: UUID) { self.server = server; self.id = id }

    func exchange(_ request: Data, reply: @escaping (Data) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let server = self.server else { reply(Data()); return }
            reply(await server.handle(request, from: self.id))
        }
    }
}

package struct IPCError: LocalizedError {
    package var errorDescription: String?
    package init(_ message: String) { errorDescription = message }
}
