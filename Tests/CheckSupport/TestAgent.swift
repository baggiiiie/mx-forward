import AgentSupport
import Foundation

/// A hardware-free XPC server that can delay replies.
@MainActor
package final class TestAgent: NSObject, NSXPCListenerDelegate {
    private let listener = NSXPCListener.anonymous()
    private var connections: [NSXPCConnection] = []
    private var held: [() -> Void] = []
    package private(set) var requests: [AgentRequest] = []
    package var hold: (AgentRequest) -> Bool = { _ in false }
    package var reply: (AgentRequest) throws -> Data
    package var endpoint: NSXPCListenerEndpoint { listener.endpoint }
    package var heldCount: Int { held.count }

    package init(reply: @escaping (AgentRequest) throws -> Data) {
        self.reply = reply
        super.init()
        listener.delegate = self
        listener.resume()
    }

    nonisolated package func listener(
        _ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        Task { @MainActor in
            connection.exportedInterface = NSXPCInterface(with: AgentProtocol.self)
            connection.exportedObject = TestPeer(server: self)
            self.connections.append(connection)
            connection.resume()
        }
        return true
    }

    fileprivate func receive(_ data: Data, reply callback: @escaping (Data) -> Void) {
        do {
            let request = try AgentCodec.decode(AgentRequest.self, from: data)
            requests.append(request)
            let data = try reply(request)
            if hold(request) { held.append { callback(data) } } else { callback(data) }
        } catch { callback(Data()) }
    }

    package func releaseReplies() {
        let replies = held
        held.removeAll()
        for reply in replies { reply() }
    }

    package func stop() {
        listener.invalidate()
        for connection in connections { connection.invalidate() }
        connections.removeAll()
        held.removeAll()
    }
}

private final class TestPeer: NSObject, AgentProtocol {
    private weak var server: TestAgent?

    @MainActor
    init(server: TestAgent) { self.server = server }

    func exchange(_ request: Data, reply: @escaping (Data) -> Void) {
        Task { @MainActor in self.server?.receive(request, reply: reply) }
    }
}
