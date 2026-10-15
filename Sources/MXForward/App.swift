import AppKit
import SwiftUI

@main
struct MXForwardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Window("MX Forward", id: "main") {
            ContentView(model: delegate.model)
        }
        .defaultSize(width: 580, height: 700)
        .windowResizability(.contentSize)
        MenuBarExtra("MX Forward", systemImage: "computermouse") {
            MenuContents(model: delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminating = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateNow }
        if model.busy {
            model.status = "Wait for the current mouse operation to finish, then quit again."
            return .terminateCancel
        }
        Task {
            let shouldQuit = await model.quitSafely()
            terminating = shouldQuit
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }
}

struct MenuContents: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.enabled ? "Mouse mappings active" : "Mouse mappings paused")
        Button("Open MX Forward") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        if model.enabled || model.needsRelease || model.preferences.resumeMappings {
            Button("Pause and restore buttons") { Task { await model.pause() } }.disabled(model.busy)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }.disabled(model.busy)
    }
}
