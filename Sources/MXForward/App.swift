import AppKit
import SettingsClient
import SwiftUI

@main
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
    let model = SettingsModel()
    private enum Termination { case idle, saving, ready }
    private var termination = Termination.idle

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch termination {
        case .ready: return .terminateNow
        case .saving: return .terminateLater
        case .idle: break
        }
        termination = .saving
        Task {
            let saved = await model.finish()
            termination = saved ? .ready : .idle
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}
