import SwiftUI
import AppKit
import ClaudeLightCore

@main
struct ClaudeLightApp: App {
    @StateObject private var watcher: SessionWatcher = {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Points at the bundled hook binary inside the running .app.
        let hookPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/claude-light-hook").path
        let installer = HookInstaller(settingsURL: settings, command: shellQuoted(hookPath))
        return SessionWatcher(
            store: SessionStore(directory: SessionStore.defaultDirectory()),
            installer: installer
        )
    }()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(watcher: watcher)
        } label: {
            // The label is the always-visible menu-bar icon, so its onAppear
            // fires at app launch (the menu's content only appears when opened).
            Image(nsImage: Self.dotImage(for: watcher.light, dim: watcher.needsAttention && !watcher.attentionPhase))
                .onAppear {
                    watcher.start()
                    DispatchQueue.main.async { offerHookInstallIfNeeded() }
                }
        }
        .menuBarExtraStyle(.menu)
    }

    /// On the very first launch, if the hooks aren't installed yet, greet the
    /// user once and offer to install them. Records that we asked so it never
    /// nags again — the menu's Install action remains the fallback.
    private func offerHookInstallIfNeeded() {
        let askedKey = "didOfferHookInstall"
        let defaults = UserDefaults.standard
        guard !watcher.hooksInstalled, !defaults.bool(forKey: askedKey) else { return }
        defaults.set(true, forKey: askedKey)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Welcome to Claude Light"
        alert.informativeText = """
        Claude Light shows a menu-bar light for your Claude Code sessions: \
        orange while an agent is working, red when one needs your input, and \
        green when it's idle.

        To do that, it adds a small hook to your Claude Code settings \
        (~/.claude/settings.json). You can remove it anytime from the menu.
        """
        alert.addButton(withTitle: "Install Hooks")
        alert.addButton(withTitle: "Not Now")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            watcher.installHooks()
        }
    }

    /// Renders the status dot as a NON-template `NSImage` so the menu bar keeps
    /// the real color. A template image (the default for SF Symbols) is coerced
    /// to monochrome by the system, which is why `foregroundStyle` was ignored.
    private static func dotImage(for light: AggregateLight, dim: Bool = false) -> NSImage {
        let base: NSColor
        switch light {
        case .red: base = .systemRed
        case .orange: base = .systemOrange
        case .green: base = .systemGreen
        }
        let color = dim ? base.withAlphaComponent(0.18) : base
        let diameter: CGFloat = 13
        let inset: CGFloat = 1
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: inset, y: inset,
                                    width: diameter - inset * 2,
                                    height: diameter - inset * 2)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
