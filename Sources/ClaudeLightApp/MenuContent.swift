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
                    Text("\(session.project) — \(friendlyLabel(for: session.status))")
                } icon: {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(color(for: session.status))
                }
            }
        }
        Divider()
        Button(watcher.hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks") {
            if watcher.hooksInstalled {
                watcher.removeHooks()
            } else {
                watcher.installHooks()
            }
        }
        Button("Quit Claude Light") { NSApplication.shared.terminate(nil) }
    }

    private func color(for status: SessionStatus) -> Color {
        switch status {
        case .waiting: return .red
        case .attention: return .red
        case .running: return .orange
        case .idle: return .green
        }
    }

    private func friendlyLabel(for status: SessionStatus) -> String {
        switch status {
        case .running: return "running"
        case .waiting: return "waiting for permission"
        case .attention: return "awaiting your reply"
        case .idle: return "idle"
        }
    }
}
