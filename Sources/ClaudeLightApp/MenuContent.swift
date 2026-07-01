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
                Button {
                } label: {
                    Label {
                        Text(rowText(for: session))
                    } icon: {
                        if session.status == .error {
                            Image(nsImage: Self.warningTriangle)
                        } else {
                            Image(nsImage: Self.dot(color(for: session.status)))
                        }
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

    /// Filled colored dot as a NON-template image (menus coerce templates to mono).
    private static func dot(_ color: NSColor) -> NSImage {
        let d: CGFloat = 9
        let image = NSImage(size: NSSize(width: d, height: d))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: d, height: d)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    /// Red-tinted `exclamationmark.triangle.fill`, non-template.
    private static let warningTriangle: NSImage = {
        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        let base = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "error")?
            .withSymbolConfiguration(cfg) ?? NSImage()
        let out = NSImage(size: base.size)
        out.lockFocus()
        base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        red.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }()

    private var headerColor: NSColor {
        if watcher.icon.red != .off { return Self.red }
        if watcher.icon.orange != .off { return Self.orange }
        if watcher.icon.green != .off { return Self.green }
        return .secondaryLabelColor
    }

    private func rowText(for session: Session) -> String {
        if session.status == .error {
            let reason = watcher.errorReasons[session.sessionID] ?? "api error"
            return "\(session.project) — API error: \(reason)"
        }
        return "\(session.project) — \(friendlyLabel(for: session.status))"
    }

    private func color(for status: SessionStatus) -> NSColor {
        switch status {
        case .waiting, .attention, .error: return Self.red
        case .running: return Self.orange
        case .idle: return Self.green
        }
    }

    private func friendlyLabel(for status: SessionStatus) -> String {
        switch status {
        case .running: return "running"
        case .waiting: return "waiting for permission"
        case .attention: return "awaiting your reply"
        case .idle: return "idle"
        case .error: return "API error"
        }
    }

    private static let red = NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
    private static let orange = NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
    private static let green = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
}
