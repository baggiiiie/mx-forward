import AppKit
import SwiftUI

@main
@MainActor
enum MXForwardEntry {
    static func main() {
        if CommandLine.arguments.contains("--check-proxy") { ProxyChecks.main() }
        else { MXForwardApp.main() }
    }
}

struct MXForwardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("MX Forward", id: "main") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 1040, height: 700)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminating = false

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateNow }
        terminating = true
        Task {
            await model.finish()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
