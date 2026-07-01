import Foundation

/// The hosting-terminal identity captured for a session, used to focus it on click.
///
/// Built in the hook from the inherited environment plus a best-effort controlling
/// TTY. Pure and value-typed so the parsing is unit-testable; the actual env/`ps`
/// read lives in the hook's `main.swift`.
public struct TerminalContext: Equatable, Sendable {
    public let termProgram: String?
    public let tty: String?
    public let termSessionId: String?

    public init(termProgram: String?, tty: String?, termSessionId: String?) {
        self.termProgram = termProgram
        self.tty = tty
        self.termSessionId = termSessionId
    }

    /// Parse from an environment dictionary and a resolved (best-effort) TTY.
    /// A blank TTY becomes nil. Session id prefers iTerm, then Terminal, then Warp
    /// (Warp is captured forward-compat only — it has no tab-focus API today).
    public init(environment: [String: String], tty: String?) {
        self.termProgram = environment["TERM_PROGRAM"]
        let trimmed = tty?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tty = (trimmed?.isEmpty == false) ? trimmed : nil
        self.termSessionId = environment["ITERM_SESSION_ID"]
            ?? environment["TERM_SESSION_ID"]
            ?? environment["WARP_SESSION_ID"]
    }
}
