import ForwardCore
import Foundation
import MouseEngine

package enum AgentIdentity {
    package static let service = "local.baggie.mxforward.agent"
    package static let preferencesSuite = "local.baggie.mxforward"
    package static let protocolVersion = 2
}

@objc(MXForwardAgentProtocol)
package protocol AgentProtocol {
    func exchange(_ request: Data, reply: @escaping (Data) -> Void)
}

package struct AgentRequest: Codable {
    package enum Command: String, Codable {
        case snapshot, settings, enable, pause, discover, rewriteConfig, recording
    }
    package var version = AgentIdentity.protocolVersion
    package var command: Command
    package var preferences: Preferences?
    package var basePreferences: Preferences?
    package var recording: Bool?

    package init(
        _ command: Command, preferences: Preferences? = nil,
        basePreferences: Preferences? = nil, recording: Bool? = nil
    ) {
        self.command = command
        self.preferences = preferences
        self.basePreferences = basePreferences
        self.recording = recording
    }
}

package struct AgentState: Codable {
    package var preferences: Preferences
    package var status: String
    package var lastAction: String
    package var log: [String]
    package var enabled: Bool
    package var busy: Bool
    package var connected: Bool
    package var accessibility: Bool
    package var inputMonitoring: Bool
    package var logitechRunning: Bool
    package var needsRelease: Bool
    package var held: [UInt16]
    package var configError: String?
    package var canEnable: Bool
    package var recording: Bool

    @MainActor
    package init(_ engine: MouseEngine) {
        preferences = engine.preferences
        status = engine.status
        lastAction = engine.lastAction
        log = engine.log
        enabled = engine.enabled
        busy = engine.busy
        connected = engine.connected
        accessibility = engine.accessibility
        inputMonitoring = engine.inputMonitoring
        logitechRunning = engine.logitechRunning
        needsRelease = engine.needsRelease
        held = engine.heldControls.map(\.rawValue)
        configError = engine.configError
        canEnable = engine.canEnable
        recording = engine.isRecordingShortcut
    }
}

package struct AgentResponse: Codable {
    package var version = AgentIdentity.protocolVersion
    package var state: AgentState?
    package var error: String?

    package init(state: AgentState? = nil, error: String? = nil) {
        self.state = state
        self.error = error
    }
}

package enum AgentCodec {
    package static let maximumBytes = 256 * 1024

    package static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        try checkSize(data)
        return data
    }

    package static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try checkSize(data)
        return try JSONDecoder().decode(type, from: data)
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= maximumBytes else { throw IPCError("Agent message is too large") }
    }
}
