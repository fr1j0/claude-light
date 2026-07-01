# Focus the session's terminal on click

**Issue:** [#22](https://github.com/fr1j0/claude-light/issues/22)
**Status:** Design approved (2026-07-01)

## Problem

Dropdown session rows look clickable but do nothing. Clicking a **main session row**
should bring its hosting terminal to the front. Subagent rows stay non-interactive
(shipped in #24) — they share the parent's terminal, so the parent row is the single
pointer per session.

## Scope (v1)

- **Precise tab focus** for **iTerm2** and **Terminal.app** — land on the exact tab by
  matching the captured TTY.
- **App-level activate** for **Warp**, **VS Code**, and everything else — bring the app
  to the front (can't target the tab).
- Everything degrades gracefully: no TTY / no match / permission denied → app-level
  activate; unknown terminal → no-op. Never disrupts.

Out of scope: precise Warp tab focus. Confirmed impossible today — Warp's official
`warp://` scheme has no focus action (only `new_window`/`new_tab`/`launch`/`tab_config`),
[warpdotdev/Warp#8611](https://github.com/warpdotdev/Warp/issues/8611) requests it and is
unimplemented, and an empirical test on real hardware (`open "warp://action/focus/tab?path=$PWD"`)
**activates Warp but does not select the matching tab**. Warp Preview uses `warppreview://`
and bundle id `dev.warp.Warp-Preview`. Also out of scope: nested fan-out; a visible
"can't focus" hint (silent no-op for now).

## Architecture

### 1. Capture (hook, impure)

`claude-light-hook` runs inside the Claude Code process and inherits its environment.
In `main.swift` it gathers a `TerminalContext` and passes it into `applyHook`, which
stamps it onto the `Session`. Core stays pure (receives values, reads no env).

Captured:
- `TERM_PROGRAM` — `Apple_Terminal` / `iTerm.app` / `WarpTerminal` / `vscode` / …
- `ITERM_SESSION_ID`, `TERM_SESSION_ID`, `WARP_SESSION_ID` — per-tab ids when present
  (only iTerm/Terminal used in v1; Warp id captured forward-compat for #8611).
- **TTY** — best-effort. The hook's own stdio are pipes, so read the controlling
  terminal of the Claude process by walking parent PIDs via `ps -o tty=`. May be empty
  in detached/headless contexts → precise focus falls back to activate.

### 2. Session model

Add optional fields (snake_case, Codable): `term_program`, `tty`, `term_session_id`.
Older records decode as `nil` → not precisely focusable (app-level or no-op).
Back-compatible; no migration.

### 3. Core — pure decision (unit-tested)

```swift
public enum FocusStrategy: Equatable, Sendable {
    case iterm(tty: String)
    case terminalApp(tty: String)
    case activateApp(bundleID: String)
    case none
}
public func focusStrategy(termProgram: String?, tty: String?) -> FocusStrategy
```

Rules:
- `Apple_Terminal` + non-empty tty → `.terminalApp(tty)`; empty tty → `.activateApp("com.apple.Terminal")`
- `iTerm.app` + non-empty tty → `.iterm(tty)`; empty tty → `.activateApp("com.googlecode.iterm2")`
- `WarpTerminal` → `.activateApp("dev.warp.Warp-Stable")`
- `vscode` → `.activateApp("com.microsoft.VSCode")`
- unknown / nil `termProgram` → `.none`

Unit tests: each mapping, tty-present vs absent for iTerm/Terminal, unknown, nil.

### 4. App — execute (main row click)

The parent session row's `Button` action calls `TerminalFocuser.focus(session)`:
- `.activateApp(bundleID)` → `NSRunningApplication.runningApplications(withBundleIdentifier:)
  .first?.activate()`; if not running, `NSWorkspace.shared` opens the app. **Permission-free.**
- `.terminalApp(tty)` → AppleScript: find the Terminal tab whose `tty` == captured, set its
  window `frontmost` + `selected tab`, `activate`.
- `.iterm(tty)` → AppleScript: iterate iTerm windows/tabs/sessions, match `tty`, `select`,
  `activate`.
- `.none` → no-op.

AppleScript runs via `NSAppleScript`. On any error (incl. TCC Automation denial) or no
match → fall back to `.activateApp` for that terminal's bundle id, else no-op.

### 5. Failure & permission handling

- Precise AppleScript triggers the macOS **Automation (TCC) prompt** on first control of
  Terminal/iTerm. Denial is caught → app-level activate fallback (never needs permission).
- Empty captured tty or no matching tab → app-level activate.
- Unknown terminal → no-op. Nothing ever throws to the UI.

## Testing

- **Core `focusStrategy`** — fully unit-tested (pure).
- **`TerminalContext` capture** — the pure parsing part (e.g. picking a tty string, mapping
  env → context) is unit-tested where pure; the actual env/`ps` read in `main.swift` is thin
  and not unit-tested (matches existing hook `main.swift`).
- **Execution layer** (`TerminalFocuser`, AppleScript, NSWorkspace) — app-layer, not
  unit-tested (matches `SessionWatcher`/`MenuContent`). **Must be manually verified on an
  interactive Mac** with Terminal.app and iTerm2 open — the two tab-matching AppleScripts
  could not be validated in the headless dev environment (only Warp present there; a piped
  subprocess reports no controlling tty).

## Risks

- **TTY capture is heuristic** — depends on the hook inheriting the Claude process's
  controlling terminal. Confirmed a piped subprocess reports no tty; mitigated by the
  parent-PID walk and the activate fallback.
- **AppleScript unverified in dev** — see Testing; fail-safe by design.
- **Bundle-id drift** — Warp Preview (`dev.warp.Warp-Preview`) and VS Code Insiders differ
  from the stable ids; v1 targets stable builds, unknown variants fall through to `.none`
  (acceptable; expand later).
