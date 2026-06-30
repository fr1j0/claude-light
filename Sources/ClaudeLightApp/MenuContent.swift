import SwiftUI
import ClaudeLightCore

struct MenuContent: View {
    @ObservedObject var watcher: SessionWatcher

    var body: some View {
        if watcher.sessions.isEmpty {
            Text("No active Claude Code sessions").foregroundStyle(.secondary)
        } else {
            ForEach(watcher.sessions, id: \.sessionID) { session in
                Label {
                    Text("\(session.project) — \(session.status.rawValue)")
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(color(for: session.status))
                }
            }
        }
        Divider()
        Button(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks") {
            if watcher.hooksInstalled {
                try? watcher.installer.uninstall()
            } else {
                try? watcher.installer.install()
            }
            watcher.hooksInstalled = watcher.installer.isInstalled()
        }
        Button("Quit Claude Light") { NSApplication.shared.terminate(nil) }
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
        case .waiting: return .red
        case .running: return .orange
        case .idle: return .green
        }
    }
}
