import SwiftUI
import AppKit
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
                    Image(nsImage: Self.dot(headerColor))
                }
                .disabled(true)
                Divider()
            }
            ForEach(watcher.sessions, id: \.sessionID) { session in
                // Rendered as a Button so the row text shows at full brightness
                // (a bare Label renders as a muted, disabled-looking menu item).
                // No action is wired yet — clicking just dismisses the menu.
                Button {
                } label: {
                    Label {
                        Text(rowText(for: session))
                    } icon: {
                        Image(nsImage: Self.dot(color(for: session.status)))
                    }
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

    /// Renders the status dot as a NON-template NSImage so the menu keeps the
    /// real color. SF Symbols are coerced to monochrome template images inside a
    /// menu, which is why `foregroundStyle` was ignored on the colored dots.
    private static func dot(_ color: NSColor) -> NSImage {
        let diameter: CGFloat = 9
        let image = NSImage(size: NSSize(width: diameter, height: diameter))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: diameter, height: diameter)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private var headerColor: NSColor {
        switch watcher.icon.lamp {
        case .red: return Self.red
        case .orange: return Self.orange
        case .green: return Self.green
        case .off: return .secondaryLabelColor
        }
    }

    private func rowText(for session: Session) -> String {
        let age = relativeTime(secondsAgo: Date().timeIntervalSince(session.updatedAt))
        return "\(session.project) — \(friendlyLabel(for: session.status)) · \(age)"
    }

    private func color(for status: SessionStatus) -> NSColor {
        switch status {
        case .error, .waiting, .attention: return Self.red
        case .running: return Self.orange
        case .idle: return Self.green
        }
    }

    private func friendlyLabel(for status: SessionStatus) -> String {
        switch status {
        case .error: return "error"
        case .running: return "running"
        case .waiting: return "waiting for permission"
        case .attention: return "awaiting your reply"
        case .idle: return "idle"
        }
    }

    // Match the lit-lamp colors used by TrafficLightIcon.
    private static let red = NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
    private static let orange = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
    private static let green = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
}
