# Session Liveness (API-error detection) + Additive Error Lamp — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a running session that hit an API error (from its transcript) and surface it as a red-blinking **error** state that layers additively over the existing single aggregate lamp, with the failing process flagged in the dropdown by a red warning triangle.

**Architecture:** All detection and state logic is pure in `ClaudeLightCore` (a new `apiErrorReason` transcript scan; `SessionStatus.error`; a multi-lamp `IconState`). The `SessionWatcher` overlays `.error` onto running sessions each 30 s refresh via a bounded transcript tail-read. The renderer lights each lamp independently so red can blink while orange breathes.

**Tech Stack:** Swift 5.9, SwiftUI `MenuBarExtra(.menu)`, AppKit (`NSImage`, `NSBezierPath`, SF Symbols), Foundation `JSONSerialization`/`FileHandle`, XCTest.

## Global Constraints

- swift-tools-version 5.9; platform floor macOS 13. Do not raise.
- `ClaudeLightCore` is pure — no AppKit/SwiftUI imports. Only it has a test target (`ClaudeLightCoreTests`). `swift test` builds Core + tests, NOT the app/hook executables, so Core tasks may land while the app targets temporarily fail to compile; the app tasks restore `swift build`.
- Swift strict concurrency: never reference a captured optional `var self` inside a concurrently-executing `Task`. Bind first: `guard let self else { return }` then `Task { @MainActor in self.method() }`. (The release CI toolchain rejects the unbound form.)
- Menu-bar and dropdown color come from **non-template** `NSImage`s (`isTemplate = false`) — the menu coerces template symbols to monochrome.
- Status colors: red `srgb(1.00, 0.23, 0.19)`, orange `srgb(1.00, 0.58, 0.00)`, green `srgb(0.20, 0.78, 0.35)`.
- Transcript API-error marker: a JSONL line where `type == "assistant"` (or `message.role == "assistant"`), `message.model == "<synthetic>"`, and the text starts (case-insensitively) with `"API Error:"`.
- Bounded transcript read: last ~64 KB only.
- Commit messages: Conventional Commits; NO AI attribution / co-author trailers.
- Run `swift test` (Core) and `swift build` (app). Package via `bash scripts/package-app.sh`.

## File Structure

- Create `Sources/ClaudeLightCore/APIErrorDetection.swift` — `apiErrorReason(transcriptJSONL:)`.
- Modify `Sources/ClaudeLightCore/Session.swift` — `SessionStatus.error`; `Session.transcriptPath`.
- Modify `Sources/ClaudeLightCore/ApplyHook.swift` — persist `transcriptPath`.
- Modify `Sources/ClaudeLightCore/MenuModel.swift` — `StatusCounts.error`; error in `statusCounts`/`summaryText`/`sortedForMenu`.
- Modify `Sources/ClaudeLightCore/IconModel.swift` — multi-lamp `IconState`/`LampMotion`/`iconState`/`litAlpha`.
- Create/modify tests under `Tests/ClaudeLightCoreTests/`.
- Modify `Sources/ClaudeLightApp/TrafficLightIcon.swift` — multi-lamp renderer.
- Modify `Sources/ClaudeLightApp/SessionWatcher.swift` — bounded tail-read + error overlay + `errorReasons`.
- Modify `Sources/ClaudeLightApp/ClaudeLightApp.swift` — label wiring.
- Modify `Sources/ClaudeLightApp/MenuContent.swift` — rows without time, error triangle + reason.

---

### Task 1: Core — apiErrorReason transcript detection

**Files:**
- Create: `Sources/ClaudeLightCore/APIErrorDetection.swift`
- Test: `Tests/ClaudeLightCoreTests/APIErrorDetectionTests.swift`

**Interfaces:**
- Consumes: nothing (pure string in).
- Produces: `public func apiErrorReason(transcriptJSONL: String) -> String?` — a short normalized reason if the last substantive turn is a synthetic `"API Error:"` message, else `nil`.

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeLightCoreTests/APIErrorDetectionTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class APIErrorDetectionTests: XCTestCase {
    private func syntheticError(_ text: String) -> String {
        #"{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func assistant(_ text: String) -> String {
        #"{"type":"assistant","message":{"model":"claude-opus-4-8","role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }
    private func user(_ text: String) -> String {
        #"{"type":"user","message":{"role":"user","content":"\#(text)"}}"#
    }
    private let toolResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#
    private let hookLine = #"{"type":"hook_success"}"#

    func test_trailingConnectionRefused() {
        let t = [assistant("working"), syntheticError("API Error: Unable to connect to API (ConnectionRefused)")].joined(separator: "\n")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection refused")
    }
    func test_trailingConnectionClosed() {
        let t = syntheticError("API Error: Connection closed mid-response. The response above may be incomplete.")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection closed")
    }
    func test_recovered_userRepliedAfterError() {
        let t = [syntheticError("API Error: Unable to connect to API (ConnectionRefused)"), user("retry please")].joined(separator: "\n")
        XCTAssertNil(apiErrorReason(transcriptJSONL: t))
    }
    func test_toolResultAfterError_isSkipped_stillError() {
        let t = [syntheticError("API Error: Unable to connect to API (ConnectionRefused)"), toolResult, hookLine].joined(separator: "\n")
        XCTAssertEqual(apiErrorReason(transcriptJSONL: t), "connection refused")
    }
    func test_normalTranscript_isNil() {
        let t = [user("hi"), assistant("all done")].joined(separator: "\n")
        XCTAssertNil(apiErrorReason(transcriptJSONL: t))
    }
    func test_garbageAndEmpty_isNilNoCrash() {
        XCTAssertNil(apiErrorReason(transcriptJSONL: ""))
        XCTAssertNil(apiErrorReason(transcriptJSONL: "not json\n{bad"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter APIErrorDetectionTests`
Expected: FAIL — `cannot find 'apiErrorReason' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeLightCore/APIErrorDetection.swift`:

```swift
import Foundation

/// If the LAST substantive turn of a Claude Code transcript (JSONL) is a synthetic
/// "API Error: …" assistant message, returns a short normalized reason; otherwise
/// nil (recovered, or no error). Defensive/fail-safe: unparseable lines are skipped.
public func apiErrorReason(transcriptJSONL: String) -> String? {
    let lines = transcriptJSONL.split(separator: "\n", omittingEmptySubsequences: true)
    for line in lines.reversed() {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let type = obj["type"] as? String
        let message = obj["message"] as? [String: Any]
        let role = message?["role"] as? String
        let isAssistant = type == "assistant" || role == "assistant"
        let isUser = type == "user" || role == "user"

        if isAssistant {
            if (message?["model"] as? String) == "<synthetic>" {
                // Synthetic turn: an API error (→ reason) or some other synthetic (→ nil).
                return errorReason(fromSynthetic: transcriptText(message))
            }
            if !transcriptText(message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil                      // real assistant turn → normal
            }
            continue                            // assistant tool_use w/ no text → keep scanning
        }
        if isUser {
            if !transcriptText(message).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return nil                      // real user turn → recovered
            }
            continue                            // tool_result (no text) → skip
        }
        // system / hook_success / attachment / etc → skip
    }
    return nil
}

private func transcriptText(_ message: [String: Any]?) -> String {
    guard let content = message?["content"] else { return "" }
    if let s = content as? String { return s }
    if let blocks = content as? [[String: Any]] {
        return blocks.filter { ($0["type"] as? String) == "text" }
                     .compactMap { $0["text"] as? String }
                     .joined(separator: "\n")
    }
    return ""
}

/// Short display reason if `text` is an "API Error: …" message, else nil.
private func errorReason(fromSynthetic text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()
    guard lower.hasPrefix("api error") else { return nil }
    if lower.contains("connectionrefused") || lower.contains("unable to connect") { return "connection refused" }
    if lower.contains("connection closed") { return "connection closed" }
    let afterColon = trimmed.drop(while: { $0 != ":" }).dropFirst()
    let reason = afterColon.trimmingCharacters(in: .whitespacesAndNewlines)
    return reason.isEmpty ? "api error" : String(reason.prefix(40))
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter APIErrorDetectionTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/APIErrorDetection.swift Tests/ClaudeLightCoreTests/APIErrorDetectionTests.swift
git commit -m "feat: detect trailing API-error turn in a transcript"
```

---

### Task 2: Core — Session.transcriptPath + hook persistence

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift`
- Modify: `Sources/ClaudeLightCore/ApplyHook.swift:12-18`
- Test: `Tests/ClaudeLightCoreTests/SessionTests.swift`, `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`

**Interfaces:**
- Produces: `Session.transcriptPath: String?` (Codable key `transcript_path`); `applyHook` writes it from `payload.transcriptPath`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeLightCoreTests/SessionTests.swift` (inside the existing `final class SessionTests`):

```swift
    func test_transcriptPath_roundTrips_andDefaultsNilOnOldJSON() throws {
        let s = Session(sessionID: "x", status: .running, project: "p", cwd: "/p",
                        updatedAt: Date(timeIntervalSince1970: 1000), transcriptPath: "/t.jsonl")
        let data = try ClaudeLightJSON.encoder.encode(s)
        XCTAssertEqual(try ClaudeLightJSON.decoder.decode(Session.self, from: data).transcriptPath, "/t.jsonl")

        let old = #"{"session_id":"y","status":"idle","project":"p","cwd":"/p","updated_at":"1970-01-01T00:16:40Z"}"#
        let decoded = try ClaudeLightJSON.decoder.decode(Session.self, from: Data(old.utf8))
        XCTAssertNil(decoded.transcriptPath)
    }
```

Append to `Tests/ClaudeLightCoreTests/ApplyHookTests.swift` (inside the existing test class; if a `SessionStore` temp-dir helper already exists there, reuse it — otherwise this is self-contained):

```swift
    func test_applyHook_persistsTranscriptPath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SessionStore(directory: dir)
        defer { try? FileManager.default.removeItem(at: dir) }
        let payload = HookPayload(sessionID: "s1", hookEventName: "PreToolUse", cwd: "/Users/me/proj",
                                  message: nil, transcriptPath: "/Users/me/.claude/projects/p/s1.jsonl")
        try applyHook(payload, to: store, now: Date(timeIntervalSince1970: 1000))
        let stored = try store.loadAll().first { $0.sessionID == "s1" }
        XCTAssertEqual(stored?.transcriptPath, "/Users/me/.claude/projects/p/s1.jsonl")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionTests`
Expected: FAIL — `Session` has no `transcriptPath` argument / member.

- [ ] **Step 3: Write minimal implementation**

In `Sources/ClaudeLightCore/Session.swift`, add the stored property, init parameter (defaulted so existing call sites keep compiling), and CodingKey:

```swift
public struct Session: Codable, Sendable, Equatable {
    public let sessionID: String
    public var status: SessionStatus
    public var project: String
    public var cwd: String
    public var updatedAt: Date
    public var transcriptPath: String?

    public init(sessionID: String, status: SessionStatus, project: String, cwd: String,
                updatedAt: Date, transcriptPath: String? = nil) {
        self.sessionID = sessionID
        self.status = status
        self.project = project
        self.cwd = cwd
        self.updatedAt = updatedAt
        self.transcriptPath = transcriptPath
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case project
        case cwd
        case updatedAt = "updated_at"
        case transcriptPath = "transcript_path"
    }
}
```

In `Sources/ClaudeLightCore/ApplyHook.swift`, pass the path through in the `.set` case:

```swift
    case .set(let status):
        let cwd = payload.cwd ?? ""
        let session = Session(
            sessionID: payload.sessionID,
            status: status,
            project: projectName(forCwd: cwd),
            cwd: cwd,
            updatedAt: now,
            transcriptPath: payload.transcriptPath
        )
        try store.write(session)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionTests` then `swift test --filter ApplyHookTests`
Expected: PASS both.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Sources/ClaudeLightCore/ApplyHook.swift Tests/ClaudeLightCoreTests/SessionTests.swift Tests/ClaudeLightCoreTests/ApplyHookTests.swift
git commit -m "feat: persist transcriptPath on sessions"
```

---

### Task 3: Core — SessionStatus.error + menu counts/summary/sort

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift` (enum), `Sources/ClaudeLightCore/MenuModel.swift`
- Test: `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces: `SessionStatus.error`; `StatusCounts.error: Int` (init now `init(needYou:working:idle:error:)`); `summaryText` breaks errors out; `sortedForMenu` ranks error first.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeLightCoreTests/MenuModelTests.swift` (inside the class or an extension; the `s(_:project:)` helper already exists there):

```swift
    func test_counts_includeError() {
        let c = statusCounts(for: [s(.error), s(.error), s(.running), s(.idle)])
        XCTAssertEqual(c, StatusCounts(needYou: 0, working: 1, idle: 1, error: 2))
    }
    func test_summary_errorsBreakOut() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 2, idle: 0, error: 1)), "1 error · 2 working")
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 1, working: 0, idle: 0, error: 2)), "2 errors · 1 needs you")
    }
    func test_sorted_errorFirst() {
        let order = sortedForMenu([s(.idle, project: "z"), s(.running, project: "r"),
                                   s(.error, project: "e"), s(.attention, project: "a")])
            .map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["error:e", "attention:a", "running:r", "idle:z"])
    }
```

Also update the existing `MenuModelTests` calls that construct `StatusCounts(needYou:working:idle:)` — add `error: 0` to each (the initializer gains the `error` parameter in Step 3). Find them with `grep -n "StatusCounts(needYou" Tests/ClaudeLightCoreTests/MenuModelTests.swift` and append `, error: 0` before the closing paren.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuModelTests`
Expected: FAIL — `SessionStatus` has no `.error`; `StatusCounts` has no `error`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/ClaudeLightCore/Session.swift`, add the case:

```swift
public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case attention
    case idle
    case error
}
```

Replace the three functions in `Sources/ClaudeLightCore/MenuModel.swift` (`StatusCounts`, `statusCounts`, `summaryText`, `sortedForMenu`) with:

```swift
public struct StatusCounts: Sendable, Equatable {
    public let needYou: Int   // waiting + attention
    public let working: Int   // running
    public let idle: Int
    public let error: Int
    public init(needYou: Int, working: Int, idle: Int, error: Int) {
        self.needYou = needYou
        self.working = working
        self.idle = idle
        self.error = error
    }
}

public func statusCounts(for sessions: [Session]) -> StatusCounts {
    var needYou = 0, working = 0, idle = 0, error = 0
    for session in sessions {
        switch session.status {
        case .waiting, .attention: needYou += 1
        case .running: working += 1
        case .idle: idle += 1
        case .error: error += 1
        }
    }
    return StatusCounts(needYou: needYou, working: working, idle: idle, error: error)
}

/// Words-and-counts summary for the dropdown header. nil = no live sessions.
public func summaryText(for counts: StatusCounts) -> String? {
    if counts.needYou == 0 && counts.working == 0 && counts.idle == 0 && counts.error == 0 { return nil }
    var parts: [String] = []
    if counts.error > 0 {
        parts.append(counts.error == 1 ? "1 error" : "\(counts.error) errors")
    }
    if counts.needYou > 0 {
        parts.append(counts.needYou == 1 ? "1 needs you" : "\(counts.needYou) need you")
    }
    if counts.working > 0 {
        parts.append("\(counts.working) working")
    }
    if parts.isEmpty { return "Idle" }   // only idle sessions
    return parts.joined(separator: " · ")
}

/// Display order for the dropdown: most urgent first, then by project name.
public func sortedForMenu(_ sessions: [Session]) -> [Session] {
    func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .error: return 0
        case .attention: return 1
        case .waiting: return 2
        case .running: return 3
        case .idle: return 4
        }
    }
    return sessions.sorted { a, b in
        let ra = rank(a.status), rb = rank(b.status)
        if ra != rb { return ra < rb }
        return a.project < b.project
    }
}
```

(Leave `relativeTime` in the file as-is — it becomes unused by the dropdown but stays for now; do not delete in this task.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuModelTests`
Expected: PASS (all MenuModel tests, new and updated).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Sources/ClaudeLightCore/MenuModel.swift Tests/ClaudeLightCoreTests/MenuModelTests.swift
git commit -m "feat: error status in counts, summary, and sort"
```

---

### Task 4: Core — multi-lamp IconState

**Files:**
- Modify: `Sources/ClaudeLightCore/IconModel.swift` (full replacement)
- Test: `Tests/ClaudeLightCoreTests/IconModelTests.swift` (full replacement)

**Interfaces:**
- Produces:
  - `public enum LampMotion: String, Sendable, Equatable { case off, steady, blink, breathe }`
  - `public struct IconState: Sendable, Equatable { let red: LampMotion; let orange: LampMotion; let green: LampMotion; var isAnimating: Bool }`
  - `public func iconState(for sessions: [Session]) -> IconState` (model-B rules)
  - `public func litAlpha(for motion: LampMotion, phase: Double) -> Double`

- [ ] **Step 1: Write the failing test**

Replace `Tests/ClaudeLightCoreTests/IconModelTests.swift` with:

```swift
import XCTest
@testable import ClaudeLightCore

final class IconModelTests: XCTestCase {
    private func s(_ status: SessionStatus) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }
    private func st(_ r: LampMotion, _ o: LampMotion, _ g: LampMotion) -> IconState {
        IconState(red: r, orange: o, green: g)
    }

    func test_none_allOff()          { XCTAssertEqual(iconState(for: []), st(.off, .off, .off)) }
    func test_idleOnly_green()       { XCTAssertEqual(iconState(for: [s(.idle)]), st(.off, .off, .steady)) }
    func test_runningOnly_orange()   { XCTAssertEqual(iconState(for: [s(.running)]), st(.off, .breathe, .off)) }
    func test_waitingRunning_singleRedSteady() {
        XCTAssertEqual(iconState(for: [s(.waiting), s(.running)]), st(.steady, .off, .off))
    }
    func test_attentionRunning_singleRedBlink() {
        XCTAssertEqual(iconState(for: [s(.attention), s(.running)]), st(.blink, .off, .off))
    }
    func test_errorRunning_redBlinkPlusOrangeBreathe() {
        XCTAssertEqual(iconState(for: [s(.error), s(.running)]), st(.blink, .breathe, .off))
    }
    func test_errorOnly_redBlink()   { XCTAssertEqual(iconState(for: [s(.error)]), st(.blink, .off, .off)) }
    func test_errorIdle_redBlink_greenSuppressed() {
        XCTAssertEqual(iconState(for: [s(.error), s(.idle)]), st(.blink, .off, .off))
    }

    func test_isAnimating() {
        XCTAssertTrue(st(.blink, .off, .off).isAnimating)
        XCTAssertTrue(st(.off, .breathe, .off).isAnimating)
        XCTAssertFalse(st(.steady, .off, .steady).isAnimating)
        XCTAssertFalse(st(.off, .off, .off).isAnimating)
    }

    func test_litAlpha_offSteady() {
        XCTAssertEqual(litAlpha(for: .off, phase: 3.2), 0.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .steady, phase: 3.2), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_blink() {
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.3), 0.2, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .blink, phase: 0.6), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_breathe() {
        XCTAssertEqual(litAlpha(for: .breathe, phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: .breathe, phase: 0.75), 0.55, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IconModelTests`
Expected: FAIL — `LampMotion` / new `IconState` init not found.

- [ ] **Step 3: Write minimal implementation**

Replace `Sources/ClaudeLightCore/IconModel.swift` with:

```swift
import Foundation

public enum LampMotion: String, Sendable, Equatable {
    case off, steady, blink, breathe
}

/// Per-lamp motion for the traffic-light icon. Red and orange can be lit at the
/// same time (error + running); green lights only as the resting baseline.
public struct IconState: Sendable, Equatable {
    public let red: LampMotion      // off | steady | blink
    public let orange: LampMotion   // off | breathe
    public let green: LampMotion    // off | steady
    public init(red: LampMotion, orange: LampMotion, green: LampMotion) {
        self.red = red
        self.orange = orange
        self.green = green
    }
    /// True when any lamp needs the animation clock running.
    public var isAnimating: Bool { red == .blink || orange == .breathe }
}

/// Model B: today's single aggregate lamp (red > orange > green) with `error`
/// layered on additively as a blinking red that does NOT suppress the base.
public func iconState(for sessions: [Session]) -> IconState {
    let hasError = sessions.contains { $0.status == .error }
    let hasAttention = sessions.contains { $0.status == .attention }
    let hasWaiting = sessions.contains { $0.status == .waiting }
    let hasRunning = sessions.contains { $0.status == .running }
    let hasIdle = sessions.contains { $0.status == .idle }

    let red: LampMotion = (hasError || hasAttention) ? .blink : (hasWaiting ? .steady : .off)
    // Orange is suppressed by a base-red (waiting/attention) but NOT by error.
    let orange: LampMotion = (hasRunning && !hasWaiting && !hasAttention) ? .breathe : .off
    // Green only when nothing else is active at all.
    let green: LampMotion = (hasIdle && !hasError && !hasRunning && !hasWaiting && !hasAttention) ? .steady : .off

    return IconState(red: red, orange: orange, green: green)
}

/// Alpha for a lamp with the given motion at `phase` seconds. Pure so it is
/// unit-testable; the app advances `phase` via a timer.
public func litAlpha(for motion: LampMotion, phase: Double) -> Double {
    switch motion {
    case .off:
        return 0.0
    case .steady:
        return 1.0
    case .blink:
        let t = phase.truncatingRemainder(dividingBy: 0.6)
        return t < 0.3 ? 1.0 : 0.2
    case .breathe:
        let cycle = phase.truncatingRemainder(dividingBy: 1.5) / 1.5     // 0..1
        let c = cos(2 * Double.pi * cycle)                                // 1 → -1
        return 0.55 + 0.45 * (0.5 + 0.5 * c)                              // 1.0 … 0.55
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IconModelTests` then the full Core suite `swift test`.
Expected: PASS (`swift test` green; the app executables are not built by `swift test`).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/IconModel.swift Tests/ClaudeLightCoreTests/IconModelTests.swift
git commit -m "feat: multi-lamp IconState with additive error lamp (model B)"
```

---

### Task 5: App — multi-lamp renderer

**Files:**
- Modify: `Sources/ClaudeLightApp/TrafficLightIcon.swift` (replace `image(...)` signature + body; keep geometry and `litColor`)

**Interfaces:**
- Consumes: `IconState`, `LampMotion`, `litAlpha(for:phase:)`.
- Produces: `static func image(state: IconState, phase: Double, mono: NSColor) -> NSImage`.

> App target has no test target — verified by `swift build` (after Task 7) + manual. This task alone still leaves the app not building (callers updated in Tasks 6–7).

- [ ] **Step 1: Replace the renderer**

In `Sources/ClaudeLightApp/TrafficLightIcon.swift`, replace the `static func image(lamp:litAlpha:mono:)` method with the multi-lamp version (keep `size`, the housing/bar geometry, and the private `litColor(_:)` exactly as they are — only the lamp loop and signature change):

```swift
    static func image(state: IconState, phase: Double, mono: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let stroke: CGFloat = 1.6
        let housing = NSRect(origin: .zero, size: size).insetBy(dx: stroke/2 + 0.5, dy: stroke/2 + 0.5)
        let radius = housing.width * 0.30
        let outline = NSBezierPath(roundedRect: housing, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        mono.setStroke()
        outline.stroke()

        let lamps: [(IconLamp, LampMotion)] = [(.red, state.red), (.orange, state.orange), (.green, state.green)]
        let innerTop = housing.maxY - housing.width * 0.20
        let innerBot = housing.minY + housing.width * 0.20
        let span = innerTop - innerBot
        let centers = [innerTop, (innerTop + innerBot) / 2, innerBot]
        let barW = housing.width * 0.60
        let barH = span / 3 * 0.78
        let barR = barH * 0.22

        for i in 0..<3 {
            let (lamp, motion) = lamps[i]
            let rect = NSRect(x: housing.midX - barW/2, y: centers[i] - barH/2, width: barW, height: barH)
            let fill = motion == .off
                ? mono.withAlphaComponent(0.28)
                : litColor(lamp).withAlphaComponent(CGFloat(litAlpha(for: motion, phase: phase)))
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: barR, yRadius: barR).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }
```

- [ ] **Step 2: Verify Core still builds and tests pass**

Run: `swift test`
Expected: PASS (renderer isn't compiled by `swift test`; this confirms nothing in Core broke).

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/TrafficLightIcon.swift
git commit -m "feat: render each traffic-light lamp independently"
```

---

### Task 6: App — SessionWatcher error overlay + tail-read

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift`

**Interfaces:**
- Consumes: `apiErrorReason`, `iconState`, `litAlpha`(indirect), `statusCounts`, `summaryText`, `sortedForMenu`, `liveSessions`.
- Produces (published): `sessions: [Session]` (with `.error` overlaid, sorted), `errorReasons: [String: String]`, `icon: IconState`, `summary: String?`, `animationPhase: Double`, `isDarkMenuBar: Bool`.

- [ ] **Step 1: Add the tail-read helper + published errorReasons**

In `Sources/ClaudeLightApp/SessionWatcher.swift`, add a published property next to the others:

```swift
    @Published private(set) var errorReasons: [String: String] = [:]
```

Add this private helper method to the class:

```swift
    /// Reads the last `maxBytes` of a transcript file (whole file if smaller).
    /// Fail-safe: returns nil on any error. A partial first line is fine —
    /// `apiErrorReason` scans bottom-up and skips unparseable lines.
    private func transcriptTail(path: String, maxBytes: Int = 64 * 1024) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return nil }
        let start = end > UInt64(maxBytes) ? end - UInt64(maxBytes) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
```

- [ ] **Step 2: Rewrite `reload()` to overlay `.error`**

Replace the body of `reload()` with:

```swift
    func reload() {
        let all = (try? store.loadAll()) ?? []
        var live = liveSessions(all, now: Date())
        var reasons: [String: String] = [:]
        for i in live.indices where live[i].status == .running {
            if let path = live[i].transcriptPath,
               let tail = transcriptTail(path: path),
               let reason = apiErrorReason(transcriptJSONL: tail) {
                live[i].status = .error
                reasons[live[i].sessionID] = reason
            }
        }
        let sorted = sortedForMenu(live)
        self.sessions = sorted
        self.errorReasons = reasons
        let state = iconState(for: sorted)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: sorted))
        updateClock(animating: state.isAnimating)
    }
```

(If the current `reload()` referenced `state.blink || state.breathe` for `updateClock`, it is now `state.isAnimating`. Leave `updateClock`, `start()`, the timers, appearance methods, and `startFSEvents()` unchanged — they keep the required `guard let self else { return }` before any `Task`.)

- [ ] **Step 3: Verify Core still passes**

Run: `swift test`
Expected: PASS. (`swift build` will still fail — `ClaudeLightApp.swift` uses the old label signature; fixed in Task 7.)

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/SessionWatcher.swift
git commit -m "feat: overlay error state from a bounded transcript tail-read"
```

---

### Task 7: App — wire the menu-bar label

**Files:**
- Modify: `Sources/ClaudeLightApp/ClaudeLightApp.swift` (the `label:` closure)

**Interfaces:**
- Consumes: `TrafficLightIcon.image(state:phase:mono:)`, `watcher.icon`, `watcher.animationPhase`, `watcher.isDarkMenuBar`.

- [ ] **Step 1: Replace the label image call**

In `Sources/ClaudeLightApp/ClaudeLightApp.swift`, replace the `Image(nsImage: TrafficLightIcon.image(...))` expression with:

```swift
            Image(nsImage: TrafficLightIcon.image(
                state: watcher.icon,
                phase: watcher.animationPhase,
                mono: watcher.isDarkMenuBar ? .white : .black))
```

Leave the `.onAppear { … }` block and `offerHookInstallIfNeeded()` unchanged.

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: FAIL only in `MenuContent.swift` (its `color(for:)`/`friendlyLabel(for:)` switches are not yet exhaustive over `.error`). Confirm there are NO errors in `ClaudeLightApp.swift`, `SessionWatcher.swift`, or `TrafficLightIcon.swift`. (SourceKit/IDE may lag; the compiler is authoritative.)

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/ClaudeLightApp.swift
git commit -m "feat: drive the menu-bar label from multi-lamp IconState"
```

---

### Task 8: App — dropdown rows (no time, error triangle + reason)

**Files:**
- Modify: `Sources/ClaudeLightApp/MenuContent.swift` (full replacement)

**Interfaces:**
- Consumes: `watcher.sessions`, `watcher.errorReasons`, `watcher.icon`, `watcher.summary`, `watcher.hooksInstalled`, `installHooks()/removeHooks()`.

- [ ] **Step 1: Replace the file**

Replace `Sources/ClaudeLightApp/MenuContent.swift` with:

```swift
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
```

- [ ] **Step 2: Build and run the full suite**

Run: `swift build && swift test`
Expected: `Build complete!` and all tests pass (Core suite green; app compiles).

- [ ] **Step 3: Manual verification (visual checkpoint)**

Run: `bash scripts/package-app.sh` then quit any running instance and `open "dist/Claude Light.app"`. Verify:
- Two hand-crafted sessions in `~/.claude-light/sessions/` (write JSON files with a recent `updated_at`): session A `running` with `transcript_path` pointing at a small JSONL whose LAST line is a synthetic `"API Error: Unable to connect to API (ConnectionRefused)"`; session B `running` with a normal transcript.
- Within 30 s: the menu-bar icon shows **red blinking + orange breathing** (two lamps). Dropdown: `⚠ A — API error: connection refused` sorted above `🟠 B — running`; header reads `1 error · 1 working`; no elapsed-time suffixes.
- Append a normal assistant line to A's transcript → within 30 s A leaves error (icon returns to a single orange breathing lamp).

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/MenuContent.swift
git commit -m "feat: dropdown error rows with warning triangle; drop elapsed time"
```

---

## Self-Review

**Spec coverage:**
- API-error detection (`apiErrorReason`, synthetic marker, reason normalization, self-healing) → Task 1 + Task 6. ✔
- `transcriptPath` persisted by the hook → Task 2. ✔
- `SessionStatus.error`; counts/summary/sort with error → Task 3. ✔
- Multi-lamp model-B `iconState` + `litAlpha` per motion → Task 4; renderer → Task 5; label → Task 7. ✔
- Additive error lamp (`error+running → red blink + orange breathe`; `waiting+running → single red`) → Task 4 tests + Task 5/7. ✔
- Dropdown: no elapsed time, error row red warning triangle + `API error: <reason>`, error-first sort, error-breakout header → Task 8 + Task 3. ✔
- Bounded ~64 KB tail-read; ≤30 s latency via existing refresh → Task 6. ✔
- Edge cases: no `transcriptPath` → skipped (Task 6 loop guard); unreadable/huge → `transcriptTail` fail-safe; error→recovery auto-clears (re-derived each reload, Task 1 recovered test + Task 6). ✔

**Placeholder scan:** none — every code/test step is complete.

**Type consistency:** `apiErrorReason(transcriptJSONL:) -> String?`, `Session.transcriptPath`, `SessionStatus.error`, `StatusCounts(needYou:working:idle:error:)`, `LampMotion`, `IconState(red:orange:green:)` + `.isAnimating`, `iconState(for:) -> IconState`, `litAlpha(for: LampMotion, phase:)`, `TrafficLightIcon.image(state:phase:mono:)`, and `SessionWatcher.errorReasons` are used identically across tasks.
