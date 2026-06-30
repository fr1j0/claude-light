import SwiftUI
import ClaudeLightCore

struct MenuContent: View {
    @ObservedObject var watcher: SessionWatcher
    let installer: HookInstaller

    @State private var hooksInstalled = false

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
        Button(hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks") {
            if hooksInstalled {
                try? installer.uninstall()
            } else {
                try? installer.install()
            }
            hooksInstalled.toggle()
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
