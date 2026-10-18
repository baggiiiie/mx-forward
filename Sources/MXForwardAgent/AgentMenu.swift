import AppKit
import MouseEngine
import AgentSupport

/// Native menu-bar controls only. SwiftUI and settings windows live in the other process.
@MainActor
final class AgentMenu: NSObject {
    private let engine: MouseEngine
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let status = NSMenuItem(title: "Connecting…", action: nil, keyEquivalent: "")
    private let toggle = NSMenuItem(title: "Enable mappings", action: nil, keyEquivalent: "")

    init(engine: MouseEngine) {
        self.engine = engine
        super.init()
        item.button?.image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MX Forward")
        let menu = NSMenu()
        menu.autoenablesItems = false
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Open MX Forward Settings", action: #selector(openSettings), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        toggle.target = self
        toggle.action = #selector(toggleMappings)
        menu.addItem(toggle)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Stop agent and disable startup", action: #selector(uninstall), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.toolTip = "MX Forward Agent"
        menu.delegate = self
    }

    @objc private func openSettings() {
        // .../MX Forward.app/Contents/Library/LoginItems/MX Forward Agent.app
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.open(app)
    }

    @objc private func toggleMappings() {
        Task {
            if engine.enabled || engine.needsRelease || engine.preferences.resumeMappings { await engine.pause() }
            else { await engine.enable() }
        }
    }

    @objc private func uninstall() {
        Task {
            do { try await AgentService.uninstall() }
            catch { fputs("Cannot uninstall agent: \(error.localizedDescription)\n", stderr) }
        }
    }
}

extension AgentMenu: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        status.title = engine.status
        let active = engine.enabled || engine.needsRelease || engine.preferences.resumeMappings
        toggle.title = active ? "Pause and restore controls" : "Enable mappings"
        toggle.isEnabled = !engine.busy && (active || engine.canEnable)
    }
}
