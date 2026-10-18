import Foundation

@MainActor
package final class AgentConnection {
    private struct Pending {
        let connection: NSXPCConnection
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }

    private var connection: NSXPCConnection?
    private var pending: [UUID: Pending] = [:]
    private let endpoint: NSXPCListenerEndpoint?
    private let serviceName: String
    private let requestTimeout: Duration

    package init(
        endpoint: NSXPCListenerEndpoint? = nil,
        serviceName: String = AgentIdentity.service,
        requestTimeout: Duration = .seconds(40)
    ) {
        self.endpoint = endpoint
        self.serviceName = serviceName
        self.requestTimeout = requestTimeout
    }

    deinit { connection?.invalidate() }

    package func close() {
        if let connection { fail(connection, with: IPCError("Connection closed")) }
    }

    package func exchange(_ request: AgentRequest) async throws -> AgentResponse {
        try Task.checkCancellation()
        let data = try AgentCodec.encode(request)
        let current = connection ?? connect()
        let id = UUID()
        do {
            let result: Data = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    let timeout = Task { [weak self] in
                        do { try await Task.sleep(for: self?.requestTimeout ?? .zero) } catch { return }
                        self?.fail(current, with: IPCError("Mouse agent response timed out"))
                    }
                    pending[id] = Pending(connection: current, continuation: continuation, timeout: timeout)
                    let proxy =
                        current.remoteObjectProxyWithErrorHandler { [weak self] error in
                            Task { @MainActor in self?.fail(current, with: error) }
                        } as? AgentProtocol
                    guard let proxy else {
                        fail(current, with: IPCError("Mouse agent is unavailable"))
                        return
                    }
                    proxy.exchange(data) { [weak self] reply in
                        Task { @MainActor in self?.complete(id, with: .success(reply)) }
                    }
                }
            } onCancel: { [weak self] in
                Task { @MainActor in self?.complete(id, with: .failure(CancellationError())) }
            }
            let response = try AgentCodec.decode(AgentResponse.self, from: result)
            guard response.version == AgentIdentity.protocolVersion else {
                throw IPCError("Agent/UI version mismatch. Restart the agent after updating.")
            }
            guard response.state != nil || response.error != nil else {
                throw IPCError("Invalid agent response")
            }
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            fail(current, with: error)
            throw error
        }
    }

    private func connect() -> NSXPCConnection {
        let current =
            endpoint.map(NSXPCConnection.init(listenerEndpoint:))
            ?? NSXPCConnection(machServiceName: serviceName)
        current.remoteObjectInterface = NSXPCInterface(with: AgentProtocol.self)
        let disconnected: () -> Void = { [weak self, weak current] in
            Task { @MainActor in
                guard let current else { return }
                self?.fail(current, with: IPCError("Mouse agent disconnected"))
            }
        }
        current.interruptionHandler = disconnected
        current.invalidationHandler = disconnected
        connection = current
        current.resume()
        return current
    }

    private func complete(_ id: UUID, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func fail(_ current: NSXPCConnection, with error: Error) {
        if connection === current { connection = nil }
        current.invalidate()
        for id in pending.keys.filter({ pending[$0]?.connection === current }) {
            complete(id, with: .failure(error))
        }
    }
}
