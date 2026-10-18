import AgentSupport
import AppKit
import Combine
import Darwin
import MouseEngine

@main
@MainActor
enum MXForwardAgent {
    private static var owner: FileLock?
    private static var server: AgentServer?
    private static var signals: [DispatchSourceSignal] = []
    private static var subscription: AnyCancellable?
    private static var stopping = false
    private static var menu: AgentMenu?

    static func main() {
        setbuf(stdout, nil)
        let arguments = Array(CommandLine.arguments.dropFirst())
        let offline = arguments == ["--offline"]
        NSApplication.shared.setActivationPolicy(.prohibited)
        if !arguments.isEmpty && !offline {
            Task { await runCommand(arguments) }
            NSApplication.shared.run()
            return
        }
        do {
            if !offline { owner = try FileLock(url: AgentService.controllerLockURL) }
            guard let store = UserDefaults(suiteName: AgentIdentity.preferencesSuite) else {
                throw IPCError("Could not open the mouse preferences")
            }
            let engine = MouseEngine(
                mouse: BoltMouse(
                    recoveryURL: offline
                        ? nil
                        : ConfigJSON.defaultURL
                            .deletingLastPathComponent().appendingPathComponent("hardware-restore.json")),
                configURL: offline ? nil : ConfigJSON.defaultURL,
                initialPreferences: offline ? Preferences() : Preferences.load(defaults: store),
                startsHardware: !offline, persistsSettings: !offline, preferenceStore: store)
            subscription = engine.$status.removeDuplicates().sink { print($0) }
            if !offline {
                NSApplication.shared.setActivationPolicy(.accessory)
                menu = AgentMenu(engine: engine)
            }
            let testService =
                offline ? ProcessInfo.processInfo.environment["MX_FORWARD_AGENT_TEST_SERVICE"] : nil
            let listener =
                offline && testService == nil
                ? NSXPCListener.anonymous()
                : NSXPCListener(machServiceName: testService ?? AgentIdentity.service)
            let service = AgentServer(engine: engine, listener: listener)
            server = service
            service.start()
            for number in [SIGINT, SIGTERM] {
                signal(number, SIG_IGN)
                let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
                source.setEventHandler { Task { @MainActor in await stop() } }
                source.resume()
                signals.append(source)
            }
            NSApplication.shared.run()
        } catch {
            fputs("MX Forward Agent: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runCommand(_ arguments: [String]) async {
        do {
            switch arguments.first {
            case "--install" where arguments.count == 2:
                try await AgentService.installAndStart(appURL: URL(fileURLWithPath: arguments[1]))
                print("Mouse agent installed and started")
            case "--uninstall" where arguments.count == 1:
                try await AgentService.uninstall()
                print("Mouse agent stopped; startup disabled")
            case "--status" where arguments.count == 1,
                "--pause" where arguments.count == 1,
                "--enable" where arguments.count == 1:
                let command: AgentRequest.Command =
                    arguments[0] == "--status"
                    ? .snapshot
                    : arguments[0] == "--pause" ? .pause : .enable
                let client = AgentConnection(
                    serviceName: ProcessInfo.processInfo.environment[
                        "MX_FORWARD_AGENT_TEST_SERVICE"] ?? AgentIdentity.service)
                let response = try await client.exchange(AgentRequest(command))
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(response), as: UTF8.self))
                client.close()
                if response.error != nil { exit(1) }
            case "--help" where arguments.count == 1:
                print(
                    "MXForwardAgent [--status | --pause | --enable | --install APP_PATH | --uninstall | --offline]"
                )
            default: throw IPCError("Unknown arguments; use --help")
            }
            exit(0)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func stop() async {
        guard !stopping, let server else { return }
        stopping = true
        let restored = await server.stop()
        if !restored { fputs("Restoration failed; power-cycle the mouse.\n", stderr) }
        exit(restored ? 0 : 1)
    }
}
