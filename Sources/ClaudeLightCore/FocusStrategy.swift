import Foundation

/// How to bring a session's hosting terminal to the front when its row is clicked.
///
/// Precise-tab strategies (`iterm`, `terminalApp`) match the captured TTY; the app
/// layer falls back to `activateApp` if the AppleScript fails, permission is denied,
/// or no tab matches. `none` means we can't identify the terminal — no-op.
public enum FocusStrategy: Equatable, Sendable {
    case iterm(tty: String)
    case terminalApp(tty: String)
    case activateApp(bundleID: String)
    case none
}

/// Pure decision: pick a focus strategy from the captured `TERM_PROGRAM` and TTY.
///
/// iTerm2 / Terminal.app with a non-empty TTY → precise tab focus; without a TTY they
/// fall back to activating the app. Warp and VS Code always activate the app (Warp has
/// no tab-focus API). Unknown or missing `termProgram` → `.none`.
public func focusStrategy(termProgram: String?, tty: String?) -> FocusStrategy {
    let hasTTY = !(tty ?? "").isEmpty
    switch termProgram {
    case "Apple_Terminal":
        return hasTTY ? .terminalApp(tty: tty!) : .activateApp(bundleID: "com.apple.Terminal")
    case "iTerm.app":
        return hasTTY ? .iterm(tty: tty!) : .activateApp(bundleID: "com.googlecode.iterm2")
    case "WarpTerminal":
        return .activateApp(bundleID: "dev.warp.Warp-Stable")
    case "vscode":
        return .activateApp(bundleID: "com.microsoft.VSCode")
    default:
        return .none
    }
}
