import AppKit
import Combine
import Darwin

/// Measurement prototype, not an installed LaunchAgent. Shares the production engine.
@main
@MainActor
enum HeadlessPrototype {
    private static var model: AppModel?
    private static var signals: [DispatchSourceSignal] = []
    private static var subscriptions = Set<AnyCancellable>()
    private static var stopping = false
    private static var lockDescriptor: Int32 = -1

    static func main() {
        setbuf(stdout, nil)
        let arguments = Set(CommandLine.arguments.dropFirst())
        guard arguments.isSubset(of: ["--offline", "--enable", "--help"]),
            !(arguments.contains("--offline") && arguments.contains("--enable"))
        else {
            print("Invalid arguments. Use --help.")
            exit(2)
        }
        if arguments.contains("--help") {
            print("""
                MXForwardHeadless [--offline | --enable]
                  default: discover the mouse, but do not claim controls
                  --offline: no HID access or config file access (memory baseline only)
                  --enable: enable mappings when discovery and permissions permit
                Quit the GUI first unless using --offline. Stop with SIGTERM or Ctrl-C.
                This prototype reads config.json but never saves settings or installs itself.
                """)
            return
        }
        let offline = arguments.contains("--offline")
        // The GUI's controller must be fully stopped, not just its window closed.
        if !offline && !NSRunningApplication.runningApplications(
            withBundleIdentifier: "local.baggie.mxforward"
        ).isEmpty {
            print("Quit MX Forward before starting the headless controller.")
            exit(2)
        }
        if !offline {
            let lockPath = NSTemporaryDirectory() + "mx-forward-headless-\(getuid()).lock"
            lockDescriptor = open(lockPath, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard lockDescriptor >= 0, flock(lockDescriptor, LOCK_EX | LOCK_NB) == 0 else {
                print("Another headless controller is running, or its lock is unavailable.")
                exit(2)
            }
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        var preferences = Preferences()
        preferences.resumeMappings = false
        let engine = AppModel(
            configURL: offline ? nil : ConfigJSON.defaultURL,
            initialPreferences: preferences, startsHardware: !offline, persistsSettings: false)
        model = engine
        engine.$status.removeDuplicates().sink { print($0) }.store(in: &subscriptions)
        engine.$enabled.removeDuplicates().sink { print("Mappings enabled: \($0)") }
            .store(in: &subscriptions)
        engine.$configError.compactMap { $0 }.removeDuplicates().sink { print($0) }
            .store(in: &subscriptions)
        engine.$accessibility.removeDuplicates().sink { print("Accessibility granted: \($0)") }
            .store(in: &subscriptions)
        engine.$inputMonitoring.removeDuplicates().sink { print("Input Monitoring granted: \($0)") }
            .store(in: &subscriptions)
        engine.$logitechRunning.removeDuplicates().sink { print("Logitech agent running: \($0)") }
            .store(in: &subscriptions)
        print("Test mode: \(engine.preferences.testMode)")
        print("Headless PID: \(getpid()); offline: \(offline)")
        fflush(stdout)

        for number in [SIGINT, SIGTERM] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler {
                Task { @MainActor in await stop() }
            }
            source.resume()
            signals.append(source)
        }
        if arguments.contains("--enable") {
            Task {
                while !stopping && !engine.enabled {
                    if engine.canEnable { await engine.enable() }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
        NSApplication.shared.run()
    }

    private static func stop() async {
        guard !stopping, let model else { return }
        stopping = true
        // Don't exit in the middle of a claim/restore operation.
        while model.busy { try? await Task.sleep(for: .milliseconds(100)) }
        let restored = await model.quitSafely(showAlert: false)
        if !restored {
            print("Restoration failed. Power-cycle the mouse to restore native controls.")
        }
        fflush(stdout)
        exit(restored ? 0 : 1)
    }
}
