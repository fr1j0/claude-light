import SwiftUI
import ClaudeLightCore

struct MenuContent: View {
    @ObservedObject var watcher: SessionWatcher

    var body: some View {
        if watcher.sessions.isEmpty {
            Text("No active Claude Code sessions").foregroundStyle(.secondary)
        } else {
            if let summary = watcher.summary {
                Label {
                    Text(summary)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(headerColor)
                }
                .disabled(true)
                Divider()
            }
            ForEach(watcher.sessions, id: \.sessionID) { session in
                Label {
                    Text(rowText(for: session))
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(color(for: session.status))
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

    private var headerColor: Color {
        switch watcher.icon.lamp {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        case .off: return .secondary
        }
    }

    private func rowText(for session: Session) -> String {
        let age = relativeTime(secondsAgo: Date().timeIntervalSince(session.updatedAt))
        return "\(session.project) — \(friendlyLabel(for: session.status)) · \(age)"
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
