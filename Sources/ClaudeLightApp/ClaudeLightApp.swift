import SwiftUI
import ClaudeLightCore

@main
struct ClaudeLightApp: App {
    @StateObject private var watcher = SessionWatcher(
        store: SessionStore(directory: SessionStore.defaultDirectory())
    )

    private var installer: HookInstaller {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Points at the bundled hook binary inside the running .app.
        let hookPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/claude-light-hook").path
        return HookInstaller(settingsURL: settings, command: hookPath)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(watcher: watcher, installer: installer)
                .onAppear { watcher.start() }
        } label: {
            Image(systemName: "circle.fill")
                .foregroundStyle(tint(for: watcher.light))
        }
        .menuBarExtraStyle(.menu)
    }

    private func tint(for light: AggregateLight) -> Color {
        switch light {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }
}
