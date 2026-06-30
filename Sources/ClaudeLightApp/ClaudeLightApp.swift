import SwiftUI
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
                .onAppear { watcher.start() }
        } label: {
            Image(nsImage: Self.dotImage(for: watcher.light))
        }
        .menuBarExtraStyle(.menu)
    }

    /// Renders the status dot as a NON-template `NSImage` so the menu bar keeps
    /// the real color. A template image (the default for SF Symbols) is coerced
    /// to monochrome by the system, which is why `foregroundStyle` was ignored.
    private static func dotImage(for light: AggregateLight) -> NSImage {
        let color: NSColor
        switch light {
        case .red: color = .systemRed
        case .orange: color = .systemOrange
        case .green: color = .systemGreen
        }
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
