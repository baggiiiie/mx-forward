import Darwin
import Foundation
import MouseEngine

/// Recording stays suppressed only while a connected client is recording.
@MainActor
package final class AgentServer: NSObject, NSXPCListenerDelegate {
    private struct Client {
        let connection: NSXPCConnection
        var recording = false
    }

    private let engine: MouseEngine
    private let listener: NSXPCListener
    private var clients: [UUID: Client] = [:]
    private var stopping = false

    package init(
        engine: MouseEngine, listener: NSXPCListener = NSXPCListener(machServiceName: AgentIdentity.service)
    ) {
        self.engine = engine
        self.listener = listener
        super.init()
        listener.delegate = self
    }

    package func start() { listener.resume() }

    nonisolated package func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard connection.effectiveUserIdentifier == getuid() else { return false }
        Task { @MainActor [weak self] in
            guard let self, !self.stopping, self.clients.count < 8 else {
                connection.invalidate()
                return
            }
            let id = UUID()
            connection.exportedInterface = NSXPCInterface(with: AgentProtocol.self)
            connection.exportedObject = AgentPeer(server: self, id: id)
            connection.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.disconnect(id) }
            }
            self.clients[id] = Client(connection: connection)
            connection.resume()
        }
        return true
    }

    private func disconnect(_ id: UUID) {
        clients.removeValue(forKey: id)
        updateRecording()
    }

    private func updateRecording() {
        engine.setRecordingShortcut(clients.values.contains { $0.recording })
    }

    fileprivate func handle(_ data: Data, from id: UUID) async -> Data {
        var error: String?
        do {
            guard !stopping, clients[id] != nil else { throw IPCError("The mouse agent is stopping") }
            let request = try AgentCodec.decode(AgentRequest.self, from: data)
            guard request.version == AgentIdentity.protocolVersion else {
                throw IPCError("Agent/UI version mismatch. Restart after updating MX Forward.")
            }
            switch request.command {
            case .snapshot: break
            case .settings:
                guard let edited = request.preferences, let base = request.basePreferences else {
                    throw IPCError("Missing settings or their original values")
                }
                try engine.updatePreferences(edited, from: base)
            case .enable:
                guard engine.canEnable else { throw IPCError("Cannot enable: \(engine.status)") }
                await engine.enable()
                guard engine.enabled else { throw IPCError(engine.status) }
            case .pause:
                guard !engine.busy else { throw IPCError("Mouse operation in progress; retry Pause") }
                await engine.pause()
                guard !engine.needsRelease else { throw IPCError(engine.status) }
            case .discover: engine.discover()
            case .rewriteConfig:
                engine.rewriteConfigFile()
                if let error = engine.configError { throw IPCError(error) }
            case .recording:
                clients[id]?.recording = request.recording ?? false
                updateRecording()
            }
        } catch let caught { error = caught.localizedDescription }
        do {
            return try AgentCodec.encode(AgentResponse(state: AgentState(engine), error: error))
        } catch {
            return Data(
                "{\"version\":\(AgentIdentity.protocolVersion),\"error\":\"Agent state is too large or invalid\"}"
                    .utf8)
        }
    }

    package func stop() async -> Bool {
        guard !stopping else { return false }
        stopping = true
        listener.invalidate()
        let restored = await engine.shutdown()
        for client in clients.values { client.connection.invalidate() }
        clients.removeAll()
        return restored
    }
}

private final class AgentPeer: NSObject, AgentProtocol {
    private weak var server: AgentServer?
    private let id: UUID

    @MainActor
    init(server: AgentServer, id: UUID) {
        self.server = server
        self.id = id
    }

    func exchange(_ request: Data, reply: @escaping (Data) -> Void) {
        Task { @MainActor in
            guard let server = self.server else {
                reply(Data())
                return
            }
            reply(await server.handle(request, from: self.id))
        }
    }
}

package struct IPCError: LocalizedError {
    package let errorDescription: String?
    package init(_ message: String) { errorDescription = message }
}
