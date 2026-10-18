import Foundation

@MainActor
package final class AgentConnection {
    private var connection: NSXPCConnection?
    private let endpoint: NSXPCListenerEndpoint?
    private let serviceName: String

    package init(endpoint: NSXPCListenerEndpoint? = nil, serviceName: String = AgentIdentity.service) {
        self.endpoint = endpoint
        self.serviceName = serviceName
    }

    package func close() {
        connection?.invalidate()
        connection = nil
    }

    package func exchange(_ request: AgentRequest) async throws -> AgentResponse {
        let data = try JSONEncoder().encode(request)
        guard data.count <= AgentCodec.maximumBytes else { throw IPCError("Settings are too large") }
        let current: NSXPCConnection
        if let connection { current = connection } else {
            if let endpoint { current = NSXPCConnection(listenerEndpoint: endpoint) }
            else { current = NSXPCConnection(machServiceName: serviceName) }
            current.remoteObjectInterface = NSXPCInterface(with: AgentProtocol.self)
            current.resume()
            connection = current
        }
        do {
            let result: Data = try await withCheckedThrowingContinuation { continuation in
                let gate = ReplyGate(continuation)
                gate.timeout = Task {
                    do { try await Task.sleep(for: .seconds(40)) } catch { return }
                    gate.resolve(.failure(IPCError("Mouse agent response timed out")))
                }
                guard let proxy = current.remoteObjectProxyWithErrorHandler({ error in
                    gate.resolve(.failure(error))
                }) as? AgentProtocol else {
                    gate.resolve(.failure(IPCError("Mouse agent is unavailable")))
                    return
                }
                proxy.exchange(data) { gate.resolve(.success($0)) }
            }
            let response = try AgentCodec.decode(AgentResponse.self, from: result)
            guard response.version == AgentIdentity.protocolVersion else {
                throw IPCError("Agent/UI version mismatch. Restart the agent after updating.")
            }
            return response
        } catch {
            close()
            throw error
        }
    }
}

/// XPC error callbacks, replies, and timeout may race. Resume exactly once.
private final class ReplyGate<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    var timeout: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<T, Error>) { self.continuation = continuation }

    func resolve(_ result: Result<T, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        timeout?.cancel()
        pending.resume(with: result)
    }
}
