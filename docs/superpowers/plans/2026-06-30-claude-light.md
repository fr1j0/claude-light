# Claude Light Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS menu-bar app that shows an aggregate red/orange/green status light for all running Claude Code sessions, driven by Claude Code hooks.

**Architecture:** One Swift Package. All decision logic (hook→state mapping, Notification permission-vs-idle discrimination, aggregate rule, staleness, settings.json merge) lives in a pure, unit-tested library `ClaudeLightCore`. Two thin executables consume it: `claude-light-hook` (the CLI the hooks invoke — reads hook JSON on stdin, updates a per-session status file) and `ClaudeLightApp` (the SwiftUI `MenuBarExtra` app that watches the status folder and renders). Status flows one way: hook → status file → FSEvents → app.

**Tech Stack:** Swift 5.9+ / SwiftUI (`MenuBarExtra`, macOS 13+), Swift Package Manager, XCTest. GitHub Actions for notarized release builds. Homebrew cask for distribution.

## Global Constraints

- **Platform:** macOS 13.0+ (required for `MenuBarExtra`). `Package.swift` sets `.macOS(.v13)`.
- **Language:** Swift 5.9+, one package, one test framework (XCTest).
- **Status folder:** `~/.claude-light/sessions/`, one JSON file per session named `<session_id>.json`.
- **Session file schema (exact keys):** `session_id`, `status`, `project`, `cwd`, `updated_at`. `status` ∈ `{running, waiting, idle}`. `updated_at` is ISO-8601.
- **Hook events handled (exact strings):** `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Notification`, `Stop`, `SessionEnd`.
- **Aggregate rule:** any `waiting` → red; else any `running` → orange; else green.
- **Staleness TTL:** 1800 seconds (30 min) default.
- **Notification rule:** go `waiting` (red) ONLY for permission-type messages; the idle "waiting for your input" nudge is ignored (no state change).
- **License/naming:** Apache-2.0 + `TRADEMARK.md`. Product name "Claude Light", repo `fr1j0/claude-light`, Homebrew tap `fr1j0/claude-light`.
- **No AI attribution** in commit messages or any committed file.

---

## File Structure

```
claude-light/
├── Package.swift
├── Sources/
│   ├── ClaudeLightCore/            # pure, fully unit-tested logic
│   │   ├── Session.swift           # Session model + SessionStatus enum (Codable)
│   │   ├── HookPayload.swift       # decode hook stdin JSON
│   │   ├── NotificationClassifier.swift  # permission vs idle nudge
│   │   ├── HookAction.swift        # hook event → action mapping
│   │   ├── SessionStore.swift      # read/write/delete session files
│   │   ├── ApplyHook.swift         # payload + store → file mutation
│   │   ├── Aggregate.swift         # aggregate light + staleness filter
│   │   └── HookInstaller.swift     # settings.json merge/remove (pure transforms + disk)
│   ├── claude-light-hook/          # thin CLI: stdin → ApplyHook
│   │   └── main.swift
│   └── ClaudeLightApp/             # SwiftUI MenuBarExtra app
│       ├── ClaudeLightApp.swift    # @main App + MenuBarExtra
│       ├── SessionWatcher.swift    # FSEvents → [Session] (ObservableObject)
│       └── MenuContent.swift       # dropdown view + install/remove buttons
├── Tests/
│   └── ClaudeLightCoreTests/
│       ├── SessionTests.swift
│       ├── HookPayloadTests.swift
│       ├── NotificationClassifierTests.swift
│       ├── HookActionTests.swift
│       ├── SessionStoreTests.swift
│       ├── ApplyHookTests.swift
│       ├── AggregateTests.swift
│       └── HookInstallerTests.swift
├── scripts/
│   └── package-app.sh              # build → .app bundle
├── .github/workflows/release.yml   # build + notarize + attest + checksums
├── Casks/claude-light.rb           # Homebrew cask (lives in the tap; mirrored here)
├── LICENSE                         # Apache-2.0
├── TRADEMARK.md
└── README.md
```

---

### Task 1: Package scaffold + Session model

**Files:**
- Create: `Package.swift`
- Create: `Sources/ClaudeLightCore/Session.swift`
- Test: `Tests/ClaudeLightCoreTests/SessionTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SessionStatus: String, Codable, Sendable { case running, waiting, idle }`
  - `struct Session: Codable, Sendable, Equatable` with `let sessionID: String`, `var status: SessionStatus`, `var project: String`, `var cwd: String`, `var updatedAt: Date`, and `init(sessionID:status:project:cwd:updatedAt:)`. JSON keys: `session_id`, `status`, `project`, `cwd`, `updated_at`.
  - `enum ClaudeLightJSON` with `static let encoder: JSONEncoder` and `static let decoder: JSONDecoder` configured for ISO-8601 dates (`.iso8601`).

- [ ] **Step 1: Create `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeLight",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "ClaudeLightCore"),
        .executableTarget(
            name: "claude-light-hook",
            dependencies: ["ClaudeLightCore"]
        ),
        .executableTarget(
            name: "ClaudeLightApp",
            dependencies: ["ClaudeLightCore"]
        ),
        .testTarget(
            name: "ClaudeLightCoreTests",
            dependencies: ["ClaudeLightCore"]
        ),
    ]
)
```

Create placeholder sources so the package builds:
- `Sources/claude-light-hook/main.swift` containing `// replaced in Task 7`
- `Sources/ClaudeLightApp/ClaudeLightApp.swift` containing `// replaced in Task 9`

- [ ] **Step 2: Write the failing test**

`Tests/ClaudeLightCoreTests/SessionTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class SessionTests: XCTestCase {
    func test_session_roundTrips_throughJSON_withSnakeCaseKeys() throws {
        let date = Date(timeIntervalSince1970: 1_719_745_200) // fixed
        let session = Session(
            sessionID: "abc123",
            status: .running,
            project: "vatios",
            cwd: "/Users/x/vatios",
            updatedAt: date
        )

        let data = try ClaudeLightJSON.encoder.encode(session)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"session_id\":\"abc123\""))
        XCTAssertTrue(json.contains("\"status\":\"running\""))
        XCTAssertTrue(json.contains("\"updated_at\""))

        let decoded = try ClaudeLightJSON.decoder.decode(Session.self, from: data)
        XCTAssertEqual(decoded, session)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --filter SessionTests`
Expected: FAIL — `Session` / `ClaudeLightJSON` not defined (compile error).

- [ ] **Step 4: Write minimal implementation**

`Sources/ClaudeLightCore/Session.swift`:

```swift
import Foundation

public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case idle
}

public struct Session: Codable, Sendable, Equatable {
    public let sessionID: String
    public var status: SessionStatus
    public var project: String
    public var cwd: String
    public var updatedAt: Date

    public init(sessionID: String, status: SessionStatus, project: String, cwd: String, updatedAt: Date) {
        self.sessionID = sessionID
        self.status = status
        self.project = project
        self.cwd = cwd
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case status
        case project
        case cwd
        case updatedAt = "updated_at"
    }
}

public enum ClaudeLightJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --filter SessionTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: package scaffold and Session model"
```

---

### Task 2: Notification classifier (permission vs idle nudge)

**Files:**
- Create: `Sources/ClaudeLightCore/NotificationClassifier.swift`
- Test: `Tests/ClaudeLightCoreTests/NotificationClassifierTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `func isPermissionNotification(message: String) -> Bool` — true when the Notification message indicates Claude is blocked awaiting the user's permission/approval; false for the idle "waiting for your input" nudge or anything else.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeLightCore

final class NotificationClassifierTests: XCTestCase {
    func test_permissionMessages_areTrue() {
        XCTAssertTrue(isPermissionNotification(message: "Claude needs your permission to use Bash"))
        XCTAssertTrue(isPermissionNotification(message: "Claude needs your approval to run a command"))
        XCTAssertTrue(isPermissionNotification(message: "Permission required to edit file"))
    }

    func test_idleNudge_isFalse() {
        XCTAssertFalse(isPermissionNotification(message: "Claude is waiting for your input"))
    }

    func test_unknownOrEmpty_isFalse() {
        XCTAssertFalse(isPermissionNotification(message: ""))
        XCTAssertFalse(isPermissionNotification(message: "Some other notification"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationClassifierTests`
Expected: FAIL — `isPermissionNotification` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public func isPermissionNotification(message: String) -> Bool {
    let m = message.lowercased()
    return m.contains("permission") || m.contains("approval")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationClassifierTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/NotificationClassifier.swift Tests/ClaudeLightCoreTests/NotificationClassifierTests.swift
git commit -m "feat: classify permission vs idle notifications"
```

---

### Task 3: Hook payload decoding + event→action mapping

**Files:**
- Create: `Sources/ClaudeLightCore/HookPayload.swift`
- Create: `Sources/ClaudeLightCore/HookAction.swift`
- Test: `Tests/ClaudeLightCoreTests/HookPayloadTests.swift`
- Test: `Tests/ClaudeLightCoreTests/HookActionTests.swift`

**Interfaces:**
- Consumes: `SessionStatus` (Task 1), `isPermissionNotification` (Task 2).
- Produces:
  - `struct HookPayload: Codable, Sendable` with `let sessionID: String`, `let hookEventName: String`, `let cwd: String?`, `let message: String?`. JSON keys: `session_id`, `hook_event_name`, `cwd`, `message`.
  - `enum HookAction: Equatable, Sendable { case set(SessionStatus); case delete; case ignore }`
  - `func action(for payload: HookPayload) -> HookAction`

- [ ] **Step 1: Write the failing test (payload decoding)**

`HookPayloadTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class HookPayloadTests: XCTestCase {
    func test_decodes_minimalPayload() throws {
        let json = #"{"session_id":"s1","hook_event_name":"Stop","cwd":"/tmp/proj"}"#
        let p = try ClaudeLightJSON.decoder.decode(HookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.sessionID, "s1")
        XCTAssertEqual(p.hookEventName, "Stop")
        XCTAssertEqual(p.cwd, "/tmp/proj")
        XCTAssertNil(p.message)
    }

    func test_decodes_notificationWithMessage() throws {
        let json = #"{"session_id":"s2","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}"#
        let p = try ClaudeLightJSON.decoder.decode(HookPayload.self, from: Data(json.utf8))
        XCTAssertEqual(p.message, "Claude needs your permission to use Bash")
        XCTAssertNil(p.cwd)
    }
}
```

- [ ] **Step 2: Write the failing test (action mapping)**

`HookActionTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class HookActionTests: XCTestCase {
    private func payload(_ event: String, message: String? = nil) -> HookPayload {
        HookPayload(sessionID: "s", hookEventName: event, cwd: "/tmp/p", message: message)
    }

    func test_sessionStart_and_stop_areIdle() {
        XCTAssertEqual(action(for: payload("SessionStart")), .set(.idle))
        XCTAssertEqual(action(for: payload("Stop")), .set(.idle))
    }

    func test_prompt_and_preToolUse_areRunning() {
        XCTAssertEqual(action(for: payload("UserPromptSubmit")), .set(.running))
        XCTAssertEqual(action(for: payload("PreToolUse")), .set(.running))
    }

    func test_notification_permission_isWaiting() {
        XCTAssertEqual(action(for: payload("Notification", message: "needs your permission")), .set(.waiting))
    }

    func test_notification_idleNudge_isIgnored() {
        XCTAssertEqual(action(for: payload("Notification", message: "Claude is waiting for your input")), .ignore)
    }

    func test_sessionEnd_deletes() {
        XCTAssertEqual(action(for: payload("SessionEnd")), .delete)
    }

    func test_unknownEvent_isIgnored() {
        XCTAssertEqual(action(for: payload("PostToolUse")), .ignore)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter HookPayloadTests` then `swift test --filter HookActionTests`
Expected: FAIL — `HookPayload` / `action(for:)` not defined.

- [ ] **Step 4: Write minimal implementation**

`Sources/ClaudeLightCore/HookPayload.swift`:

```swift
import Foundation

public struct HookPayload: Codable, Sendable {
    public let sessionID: String
    public let hookEventName: String
    public let cwd: String?
    public let message: String?

    public init(sessionID: String, hookEventName: String, cwd: String?, message: String?) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.message = message
    }

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case message
    }
}
```

`Sources/ClaudeLightCore/HookAction.swift`:

```swift
import Foundation

public enum HookAction: Equatable, Sendable {
    case set(SessionStatus)
    case delete
    case ignore
}

public func action(for payload: HookPayload) -> HookAction {
    switch payload.hookEventName {
    case "SessionStart", "Stop":
        return .set(.idle)
    case "UserPromptSubmit", "PreToolUse":
        return .set(.running)
    case "Notification":
        return isPermissionNotification(message: payload.message ?? "") ? .set(.waiting) : .ignore
    case "SessionEnd":
        return .delete
    default:
        return .ignore
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter HookPayloadTests` then `swift test --filter HookActionTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeLightCore/HookPayload.swift Sources/ClaudeLightCore/HookAction.swift Tests/ClaudeLightCoreTests/HookPayloadTests.swift Tests/ClaudeLightCoreTests/HookActionTests.swift
git commit -m "feat: decode hook payload and map events to actions"
```

---

### Task 4: SessionStore (write / delete / loadAll)

**Files:**
- Create: `Sources/ClaudeLightCore/SessionStore.swift`
- Test: `Tests/ClaudeLightCoreTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `Session`, `ClaudeLightJSON` (Task 1).
- Produces:
  - `struct SessionStore` with `let directory: URL`, `init(directory: URL)`.
  - `static func defaultDirectory() -> URL` → `~/.claude-light/sessions/`.
  - `func fileURL(for sessionID: String) -> URL`
  - `func write(_ session: Session) throws` — creates `directory` if missing, atomic write.
  - `func delete(sessionID: String) throws` — no error if file already absent.
  - `func loadAll() throws -> [Session]` — decodes every `*.json`, silently skips unreadable/corrupt files; returns `[]` if directory absent.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeLightCore

final class SessionStoreTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-tests-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private func makeSession(_ id: String, _ status: SessionStatus) -> Session {
        Session(sessionID: id, status: status, project: "p", cwd: "/tmp/p",
                updatedAt: Date(timeIntervalSince1970: 1_719_745_200))
    }

    func test_write_then_loadAll_returnsSession() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
        XCTAssertEqual(all.first?.status, .running)
    }

    func test_write_isUpsert() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.write(makeSession("a", .idle))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.status, .idle)
    }

    func test_delete_removesFile_andIsIdempotent() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try store.delete(sessionID: "a")
        XCTAssertEqual(try store.loadAll().count, 0)
        XCTAssertNoThrow(try store.delete(sessionID: "a")) // already gone
    }

    func test_loadAll_onMissingDirectory_returnsEmpty() throws {
        let store = tempStore() // never created
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_loadAll_skipsCorruptFiles() throws {
        let store = tempStore()
        try store.write(makeSession("a", .running))
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL(for: "broken"))
        let all = try store.loadAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.sessionID, "a")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SessionStoreTests`
Expected: FAIL — `SessionStore` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public struct SessionStore {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-light", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func fileURL(for sessionID: String) -> URL {
        directory.appendingPathComponent("\(sessionID).json")
    }

    public func write(_ session: Session) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try ClaudeLightJSON.encoder.encode(session)
        try data.write(to: fileURL(for: session.sessionID), options: .atomic)
    }

    public func delete(sessionID: String) throws {
        let url = fileURL(for: sessionID)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public func loadAll() throws -> [Session] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let urls = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? ClaudeLightJSON.decoder.decode(Session.self, from: data)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SessionStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/SessionStore.swift Tests/ClaudeLightCoreTests/SessionStoreTests.swift
git commit -m "feat: SessionStore read/write/delete"
```

---

### Task 5: Apply a hook payload to the store

**Files:**
- Create: `Sources/ClaudeLightCore/ApplyHook.swift`
- Test: `Tests/ClaudeLightCoreTests/ApplyHookTests.swift`

**Interfaces:**
- Consumes: `HookPayload`, `action(for:)`, `SessionStore`, `Session` (Tasks 1, 3, 4).
- Produces: `func applyHook(_ payload: HookPayload, to store: SessionStore, now: Date) throws` — performs the action: `.delete` removes the file; `.set(status)` upserts a `Session` whose `project` is the last path component of `cwd` (or `"unknown"` if `cwd` is nil/empty), `updatedAt = now`; `.ignore` does nothing.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeLightCore

final class ApplyHookTests: XCTestCase {
    private func tempStore() -> SessionStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-light-apply-\(UUID().uuidString)")
        return SessionStore(directory: dir)
    }

    private let now = Date(timeIntervalSince1970: 1_719_745_200)

    func test_setAction_writesSession_withProjectFromCwd() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "UserPromptSubmit", cwd: "/Users/x/vatios", message: nil)
        try applyHook(p, to: store, now: now)
        let s = try XCTUnwrap(try store.loadAll().first)
        XCTAssertEqual(s.status, .running)
        XCTAssertEqual(s.project, "vatios")
        XCTAssertEqual(s.updatedAt, now)
    }

    func test_ignoreAction_writesNothing() throws {
        let store = tempStore()
        let p = HookPayload(sessionID: "s1", hookEventName: "Notification", cwd: "/x", message: "Claude is waiting for your input")
        try applyHook(p, to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_deleteAction_removesSession() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: "/x/p", message: nil), to: store, now: now)
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "SessionEnd", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().count, 0)
    }

    func test_missingCwd_projectIsUnknown() throws {
        let store = tempStore()
        try applyHook(HookPayload(sessionID: "s1", hookEventName: "Stop", cwd: nil, message: nil), to: store, now: now)
        XCTAssertEqual(try store.loadAll().first?.project, "unknown")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ApplyHookTests`
Expected: FAIL — `applyHook` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public func applyHook(_ payload: HookPayload, to store: SessionStore, now: Date) throws {
    switch action(for: payload) {
    case .ignore:
        return
    case .delete:
        try store.delete(sessionID: payload.sessionID)
    case .set(let status):
        let cwd = payload.cwd ?? ""
        let project = cwd.isEmpty ? "unknown" : URL(fileURLWithPath: cwd).lastPathComponent
        let session = Session(
            sessionID: payload.sessionID,
            status: status,
            project: project,
            cwd: cwd,
            updatedAt: now
        )
        try store.write(session)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ApplyHookTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/ApplyHook.swift Tests/ClaudeLightCoreTests/ApplyHookTests.swift
git commit -m "feat: apply hook payload to session store"
```

---

### Task 6: Aggregate light + staleness filter

**Files:**
- Create: `Sources/ClaudeLightCore/Aggregate.swift`
- Test: `Tests/ClaudeLightCoreTests/AggregateTests.swift`

**Interfaces:**
- Consumes: `Session`, `SessionStatus` (Task 1).
- Produces:
  - `enum AggregateLight: String, Sendable { case red, orange, green }`
  - `func liveSessions(_ sessions: [Session], now: Date, ttl: TimeInterval = 1800) -> [Session]` — drops sessions whose `updatedAt` is more than `ttl` seconds before `now`.
  - `func aggregateLight(for sessions: [Session]) -> AggregateLight` — any `.waiting` → `.red`; else any `.running` → `.orange`; else `.green` (including empty).

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeLightCore

final class AggregateTests: XCTestCase {
    private func s(_ status: SessionStatus, ageSeconds: TimeInterval = 0) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000 - ageSeconds))
    }
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func test_emptyIsGreen() {
        XCTAssertEqual(aggregateLight(for: []), .green)
    }

    func test_redWinsOverOrangeAndGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running), s(.waiting)]), .red)
    }

    func test_orangeWinsOverGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.running)]), .orange)
    }

    func test_allIdleIsGreen() {
        XCTAssertEqual(aggregateLight(for: [s(.idle), s(.idle)]), .green)
    }

    func test_liveSessions_dropsStale() {
        let fresh = s(.running, ageSeconds: 60)
        let stale = s(.waiting, ageSeconds: 3600)
        let live = liveSessions([fresh, stale], now: now, ttl: 1800)
        XCTAssertEqual(live.map(\.sessionID), [fresh.sessionID])
    }

    func test_liveSessions_keepsExactlyAtTTL() {
        let edge = s(.running, ageSeconds: 1800)
        XCTAssertEqual(liveSessions([edge], now: now, ttl: 1800).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AggregateTests`
Expected: FAIL — `aggregateLight` / `liveSessions` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

public enum AggregateLight: String, Sendable {
    case red
    case orange
    case green
}

public func liveSessions(_ sessions: [Session], now: Date, ttl: TimeInterval = 1800) -> [Session] {
    sessions.filter { now.timeIntervalSince($0.updatedAt) <= ttl }
}

public func aggregateLight(for sessions: [Session]) -> AggregateLight {
    if sessions.contains(where: { $0.status == .waiting }) { return .red }
    if sessions.contains(where: { $0.status == .running }) { return .orange }
    return .green
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AggregateTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Aggregate.swift Tests/ClaudeLightCoreTests/AggregateTests.swift
git commit -m "feat: aggregate light and staleness filter"
```

---

### Task 7: `claude-light-hook` executable

**Files:**
- Modify: `Sources/claude-light-hook/main.swift` (replace placeholder)
- (No unit test — this is a thin I/O wrapper over already-tested `applyHook`; verified manually.)

**Interfaces:**
- Consumes: `HookPayload`, `applyHook`, `SessionStore`, `ClaudeLightJSON` (Tasks 1, 4, 5).
- Produces: a CLI binary that reads hook JSON from stdin, calls `applyHook(_:to:now:)` against `SessionStore.defaultDirectory()`, and ALWAYS exits 0 (a hook must never break the user's Claude Code session, even on malformed input).

- [ ] **Step 1: Write the implementation**

`Sources/claude-light-hook/main.swift`:

```swift
import Foundation
import ClaudeLightCore

// A hook must never disrupt the Claude Code session: swallow all errors, always exit 0.
let input = FileHandle.standardInput.readDataToEndOfFile()

if let payload = try? ClaudeLightJSON.decoder.decode(HookPayload.self, from: input) {
    let store = SessionStore(directory: SessionStore.defaultDirectory())
    try? applyHook(payload, to: store, now: Date())
}

exit(0)
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds with no errors.

- [ ] **Step 3: Manual verification — running event**

Run:
```bash
echo '{"session_id":"manual1","hook_event_name":"UserPromptSubmit","cwd":"/tmp/demo"}' \
  | swift run claude-light-hook
cat ~/.claude-light/sessions/manual1.json
```
Expected: file exists; `"status":"running"`, `"project":"demo"`.

- [ ] **Step 4: Manual verification — permission vs idle vs end**

Run:
```bash
echo '{"session_id":"manual1","hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}' | swift run claude-light-hook
cat ~/.claude-light/sessions/manual1.json   # status: waiting

echo '{"session_id":"manual1","hook_event_name":"Stop","cwd":"/tmp/demo"}' | swift run claude-light-hook
cat ~/.claude-light/sessions/manual1.json   # status: idle

echo '{"session_id":"manual1","hook_event_name":"Notification","message":"Claude is waiting for your input"}' | swift run claude-light-hook
cat ~/.claude-light/sessions/manual1.json   # STILL idle (idle nudge ignored)

echo '{"session_id":"manual1","hook_event_name":"SessionEnd"}' | swift run claude-light-hook
ls ~/.claude-light/sessions/manual1.json    # No such file
```
Expected: each comment above holds. Clean up: `rm -rf ~/.claude-light/sessions/manual1.json`.

- [ ] **Step 5: Commit**

```bash
git add Sources/claude-light-hook/main.swift
git commit -m "feat: claude-light-hook CLI reads stdin and updates store"
```

---

### Task 8: Hook installer (settings.json merge / remove)

**Files:**
- Create: `Sources/ClaudeLightCore/HookInstaller.swift`
- Test: `Tests/ClaudeLightCoreTests/HookInstallerTests.swift`

**Interfaces:**
- Consumes: nothing from other tasks (operates on JSON dictionaries).
- Produces:
  - `let claudeLightHookEvents: [String]` = the six event names in Global Constraints.
  - `func installedHooks(into root: [String: Any], command: String) -> [String: Any]` — pure transform. For each event, ensures `root["hooks"][event]` is an array containing a group `{"hooks":[{"type":"command","command":command}]}` (PreToolUse's group also has `"matcher":"*"`). Idempotent: if a group already references `command` for that event, leaves it. Never removes pre-existing unrelated hook groups.
  - `func uninstalledHooks(from root: [String: Any], command: String) -> [String: Any]` — pure transform removing every inner hook whose `command` equals `command`; drops emptied groups, emptied event arrays, and an emptied `hooks` object.
  - `struct HookInstaller { let settingsURL: URL; let command: String; func install() throws; func uninstall() throws }` — load JSON (or `{}` if absent), apply the matching pure transform, write back pretty-printed.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ClaudeLightCore

final class HookInstallerTests: XCTestCase {
    let cmd = "/Applications/Claude Light.app/Contents/MacOS/claude-light-hook"

    private func commands(_ root: [String: Any], _ event: String) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any],
              let groups = hooks[event] as? [[String: Any]] else { return [] }
        return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []) }
            .compactMap { $0["command"] as? String }
    }

    func test_install_addsAllSixEvents() {
        let out = installedHooks(into: [:], command: cmd)
        for event in claudeLightHookEvents {
            XCTAssertTrue(commands(out, event).contains(cmd), "missing \(event)")
        }
    }

    func test_install_isIdempotent() {
        let once = installedHooks(into: [:], command: cmd)
        let twice = installedHooks(into: once, command: cmd)
        XCTAssertEqual(commands(twice, "Stop").filter { $0 == cmd }.count, 1)
    }

    func test_install_preservesExistingUnrelatedHooks() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let out = installedHooks(into: existing, command: cmd)
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
        XCTAssertTrue(commands(out, "Stop").contains(cmd))
    }

    func test_preToolUse_groupHasMatcher() {
        let out = installedHooks(into: [:], command: cmd)
        let hooks = out["hooks"] as! [String: Any]
        let groups = hooks["PreToolUse"] as! [[String: Any]]
        let ours = groups.first { ($0["hooks"] as? [[String: Any]])?.contains { $0["command"] as? String == cmd } == true }
        XCTAssertEqual(ours?["matcher"] as? String, "*")
    }

    func test_uninstall_removesOurs_keepsOthers() {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/other/tool"]]]]]
        ]
        let installed = installedHooks(into: existing, command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertFalse(commands(out, "Stop").contains(cmd))
        XCTAssertTrue(commands(out, "Stop").contains("/other/tool"))
    }

    func test_uninstall_fromOnlyOurs_leavesNoEmptyHooksKey() {
        let installed = installedHooks(into: [:], command: cmd)
        let out = uninstalledHooks(from: installed, command: cmd)
        XCTAssertNil(out["hooks"])
    }

    func test_diskRoundTrip_installThenUninstall() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-\(UUID().uuidString).json")
        try Data("{}".utf8).write(to: url)
        try HookInstaller(settingsURL: url, command: cmd).install()
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertTrue(commands(root, "Stop").contains(cmd))
        try HookInstaller(settingsURL: url, command: cmd).uninstall()
        root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertNil(root["hooks"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HookInstallerTests`
Expected: FAIL — `installedHooks` / `uninstalledHooks` / `HookInstaller` not defined.

- [ ] **Step 3: Write minimal implementation**

`Sources/ClaudeLightCore/HookInstaller.swift`:

```swift
import Foundation

public let claudeLightHookEvents: [String] = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "Stop", "SessionEnd"
]

private func groupCommands(_ group: [String: Any]) -> [String] {
    (group["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
}

public func installedHooks(into root: [String: Any], command: String) -> [String: Any] {
    var root = root
    var hooks = (root["hooks"] as? [String: Any]) ?? [:]

    for event in claudeLightHookEvents {
        var groups = (hooks[event] as? [[String: Any]]) ?? []
        let alreadyPresent = groups.contains { groupCommands($0).contains(command) }
        if !alreadyPresent {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            if event == "PreToolUse" { group["matcher"] = "*" }
            groups.append(group)
        }
        hooks[event] = groups
    }

    root["hooks"] = hooks
    return root
}

public func uninstalledHooks(from root: [String: Any], command: String) -> [String: Any] {
    var root = root
    guard var hooks = root["hooks"] as? [String: Any] else { return root }

    for event in claudeLightHookEvents {
        guard var groups = hooks[event] as? [[String: Any]] else { continue }
        groups = groups.compactMap { group in
            var group = group
            let inner = (group["hooks"] as? [[String: Any]] ?? [])
                .filter { ($0["command"] as? String) != command }
            if inner.isEmpty { return nil }
            group["hooks"] = inner
            return group
        }
        if groups.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = groups }
    }

    if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
    return root
}

public struct HookInstaller {
    public let settingsURL: URL
    public let command: String

    public init(settingsURL: URL, command: String) {
        self.settingsURL = settingsURL
        self.command = command
    }

    private func loadRoot() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path),
              let data = try? Data(contentsOf: settingsURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj
    }

    private func save(_ root: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try FileManager.default.createDirectory(
            at: settingsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: settingsURL, options: .atomic)
    }

    public func install() throws {
        try save(installedHooks(into: try loadRoot(), command: command))
    }

    public func uninstall() throws {
        try save(uninstalledHooks(from: try loadRoot(), command: command))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter HookInstallerTests`
Expected: PASS.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeLightCore/HookInstaller.swift Tests/ClaudeLightCoreTests/HookInstallerTests.swift
git commit -m "feat: settings.json hook installer with idempotent merge/remove"
```

---

### Task 9: Menu-bar app (SwiftUI `MenuBarExtra`)

**Files:**
- Modify: `Sources/ClaudeLightApp/ClaudeLightApp.swift` (replace placeholder)
- Create: `Sources/ClaudeLightApp/SessionWatcher.swift`
- Create: `Sources/ClaudeLightApp/MenuContent.swift`
- (UI is manual/smoke-tested per spec; logic it depends on is already unit-tested in Core.)

**Interfaces:**
- Consumes: `SessionStore`, `Session`, `liveSessions`, `aggregateLight`, `AggregateLight`, `HookInstaller`, `SessionStatus` (Core).
- Produces: a runnable menu-bar app.
  - `final class SessionWatcher: ObservableObject` with `@Published var sessions: [Session]`, `@Published var light: AggregateLight`, `init(store: SessionStore)`, `func start()` (FSEvents watch on `store.directory` + an initial `reload()` + a periodic timer to re-evaluate staleness), `func reload()` (loads, filters with `liveSessions(_:now:)`, recomputes `light`).

- [ ] **Step 1: Implement `SessionWatcher`**

`Sources/ClaudeLightApp/SessionWatcher.swift`:

```swift
import Foundation
import Combine
import CoreServices
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var light: AggregateLight = .green

    private let store: SessionStore
    private var stream: FSEventStreamRef?
    private var timer: Timer?

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        reload()
        startFSEvents()
        // Re-evaluate staleness even when no file changes.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    func reload() {
        let all = (try? store.loadAll()) ?? []
        let live = liveSessions(all, now: Date())
            .sorted { $0.project < $1.project }
        self.sessions = live
        self.light = aggregateLight(for: live)
    }

    private func startFSEvents() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<SessionWatcher>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in watcher.reload() }
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [store.directory.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        self.stream = stream
        if let stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }
}
```

- [ ] **Step 2: Implement the menu content view**

`Sources/ClaudeLightApp/MenuContent.swift`:

```swift
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
                    Image(systemName: "circle.fill").foregroundStyle(color(for: session.status))
                }
            }
        }
        Divider()
        Button(hooksInstalled ? "Remove Claude Code hooks" : "Install Claude Code hooks") {
            try? (hooksInstalled ? installer.uninstall() : installer.install())
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
```

- [ ] **Step 3: Implement the app entry point**

`Sources/ClaudeLightApp/ClaudeLightApp.swift`:

```swift
import SwiftUI
import ClaudeLightCore

@main
struct ClaudeLightApp: App {
    @StateObject private var watcher = SessionWatcher(store: SessionStore(directory: SessionStore.defaultDirectory()))

    private var installer: HookInstaller {
        let settings = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // Points at the bundled hook binary inside the running .app.
        let hookPath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/claude-light-hook").path
        return HookInstaller(settingsURL: settings, command: hookPath)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(watcher: watcher, installer: installer)
        } label: {
            Image(systemName: symbol(for: watcher.light))
                .foregroundStyle(tint(for: watcher.light))
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: watcher.light) { _ in }
    }

    private func symbol(for light: AggregateLight) -> String {
        "circle.fill"
    }

    private func tint(for light: AggregateLight) -> Color {
        switch light {
        case .red: return .red
        case .orange: return .orange
        case .green: return .green
        }
    }
}

private extension ClaudeLightApp {
    init() {
        _watcher = StateObject(wrappedValue: {
            let w = SessionWatcher(store: SessionStore(directory: SessionStore.defaultDirectory()))
            return w
        }())
    }
}
```

Note: call `watcher.start()` once on appear. Add `.task { watcher.start() }` to the `MenuContent` root, or start it in `MenuContent.onAppear`. Implementer wires whichever compiles cleanly with `MenuBarExtra` (a `.menu` style content view supports `.onAppear`).

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds with no errors. (If `@main` + custom `init` conflicts, drop the private `init` extension and start the watcher from `MenuContent.onAppear` instead — the watcher must call `start()` exactly once.)

- [ ] **Step 5: Manual smoke test**

Run `swift run ClaudeLightApp` (a menu-bar icon appears). In another terminal:
```bash
echo '{"session_id":"smoke","hook_event_name":"UserPromptSubmit","cwd":"/tmp/smoke"}' | swift run claude-light-hook
```
Expected: icon turns orange within ~1s; dropdown lists "smoke — running". Then:
```bash
echo '{"session_id":"smoke","hook_event_name":"Notification","message":"needs your permission"}' | swift run claude-light-hook
```
Expected: icon turns red. Then `SessionEnd` → icon returns to green, session disappears. Clean up `rm -rf ~/.claude-light/sessions/smoke.json`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeLightApp
git commit -m "feat: menu-bar app with FSEvents watcher and install button"
```

---

### Task 10: License, trademark, README

**Files:**
- Create: `LICENSE` (Apache-2.0 full text)
- Create: `TRADEMARK.md`
- Create: `README.md`

**Interfaces:** none (documentation).

- [ ] **Step 1: Add Apache-2.0 LICENSE**

Fetch the canonical Apache-2.0 text into `LICENSE` (copyright line: `Copyright 2026 fr1j0`).

- [ ] **Step 2: Add `TRADEMARK.md`**

```markdown
# Trademark Notice

The name "Claude Light", the project logo, and the icon are trademarks of the
maintainer and are NOT licensed under Apache-2.0.

You may fork and redistribute the source code under Apache-2.0, but you may not:
- use the name "Claude Light" for your fork or distribution, or
- present your build as the official Claude Light.

Rename your fork and use your own branding. The only official, supported builds
are those published at https://github.com/fr1j0/claude-light/releases.

"Claude" is a trademark of Anthropic; this is an independent community project,
not affiliated with or endorsed by Anthropic.
```

- [ ] **Step 3: Add `README.md`**

Cover: what it does (red/orange/green per spec), the three states, install (Homebrew tap + the one-time right-click→Open note only if a build is ever shipped un-notarized; the official build is notarized), the "Install Claude Code hooks" first-run step, "install only from official Releases" with the checksum-verification note, how the hooks/status-folder work (link the spec), and the trademark/affiliation note.

- [ ] **Step 4: Commit**

```bash
git add LICENSE TRADEMARK.md README.md
git commit -m "docs: license, trademark notice, and README"
```

---

### Task 11: Packaging + notarized release CI + Homebrew cask

**Files:**
- Create: `scripts/package-app.sh`
- Create: `.github/workflows/release.yml`
- Create: `Casks/claude-light.rb`

**Interfaces:** none (build/dist tooling). Verified by a tagged release producing a notarized, attested `.app` zip + checksums.

> This task is infrastructure, not TDD. Each step is concrete; verification is "the workflow runs green on a tag and produces the artifacts."

- [ ] **Step 1: `scripts/package-app.sh` — assemble the `.app` bundle**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Builds a release binary and lays it out as Claude Light.app, bundling the
# claude-light-hook helper at Contents/MacOS/ so the installer's hook path resolves.
APP="dist/Claude Light.app"
swift build -c release --product ClaudeLightApp
swift build -c release --product claude-light-hook
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeLightApp "$APP/Contents/MacOS/ClaudeLightApp"
cp .build/release/claude-light-hook "$APP/Contents/MacOS/claude-light-hook"
cp Resources/Info.plist "$APP/Contents/Info.plist"   # LSUIElement=true (agent app, no Dock icon)
echo "Built $APP"
```

Also create `Resources/Info.plist` with `CFBundleExecutable=ClaudeLightApp`, `CFBundleIdentifier=com.fr1j0.claude-light`, `LSUIElement=<true/>`, `CFBundleName=Claude Light`, and a version string.

- [ ] **Step 2: `.github/workflows/release.yml` — build, sign, notarize, attest, checksum**

Concrete workflow (runs on `push: tags: ['v*']`, `runs-on: macos-14`):
1. `actions/checkout@v4`.
2. `swift test` (gate the release on green tests).
3. Import Developer ID cert from `secrets.MACOS_CERT_P12` / `secrets.MACOS_CERT_PASSWORD` into a temp keychain.
4. `bash scripts/package-app.sh`.
5. `codesign --deep --options runtime --sign "Developer ID Application: <name>" "dist/Claude Light.app"`.
6. `ditto -c -k --keepParent "dist/Claude Light.app" "dist/claude-light.zip"`.
7. Notarize: `xcrun notarytool submit dist/claude-light.zip --apple-id ... --team-id ... --password ... --wait`, then `xcrun stapler staple "dist/Claude Light.app"` and re-zip.
8. `shasum -a 256 dist/claude-light.zip > dist/claude-light.zip.sha256`.
9. `actions/attest-build-provenance@v1` with `subject-path: dist/claude-light.zip`.
10. `softprops/action-gh-release@v2` uploading the zip + `.sha256`.

All Apple credentials come from repo secrets; none are committed.

- [ ] **Step 3: `Casks/claude-light.rb` — Homebrew cask**

```ruby
cask "claude-light" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_SHA256"

  url "https://github.com/fr1j0/claude-light/releases/download/v#{version}/claude-light.zip"
  name "Claude Light"
  desc "Menu-bar status light for Claude Code sessions"
  homepage "https://github.com/fr1j0/claude-light"

  app "Claude Light.app"

  caveats <<~EOS
    Launch Claude Light, then use "Install Claude Code hooks" from the menu
    to wire it into ~/.claude/settings.json.
  EOS
end
```

The tap repo is `fr1j0/homebrew-claude-light`; this file is mirrored there at `Casks/claude-light.rb`. On each release, bump `version` + `sha256` (from the release `.sha256`).

- [ ] **Step 4: Verify**

Tag a test release: `git tag v0.0.1-test && git push origin v0.0.1-test`. Confirm the workflow goes green and the release has `claude-light.zip`, `claude-light.zip.sha256`, and an attestation. Download, verify `shasum -a 256 -c`, unzip, launch, confirm `spctl -a -vv "Claude Light.app"` reports "accepted / Notarized Developer ID".

- [ ] **Step 5: Commit**

```bash
git add scripts/package-app.sh .github/workflows/release.yml Casks/claude-light.rb Resources/Info.plist
git commit -m "build: app packaging, notarized release CI, homebrew cask"
```

---

## Self-Review

**Spec coverage:**
- Menu-bar app + aggregate light + per-session dropdown → Tasks 6, 9. ✓
- Folder-of-status-files transport + schema → Tasks 1, 4. ✓
- FSEvents watch + staleness TTL → Tasks 6, 9. ✓
- Hook shim + Notification discrimination → Tasks 2, 3, 5, 7. ✓
- State machine (all six events) → Tasks 3, 7 (manual), 9 (smoke). ✓
- Aggregate red-wins → Task 6. ✓
- One-click hook installer (idempotent merge + clean remove) → Tasks 8, 9. ✓
- OSS + Apache-2.0 + trademark → Task 10. ✓
- Provenance (CI attestation + checksums) + notarization → Task 11. ✓
- Install flow (brew tap + first-run install) → Tasks 9, 11. ✓
- v1 non-goals respected (no focus/history/sounds/remote) → not implemented anywhere. ✓

**Placeholder scan:** `REPLACE_WITH_RELEASE_SHA256` in the cask is an intentional per-release value, documented as such. Apache-2.0 full text is fetched in Task 10 Step 1 rather than inlined (standard canonical document). No other placeholders.

**Type consistency:** `Session`, `SessionStatus`, `HookPayload`, `HookAction`, `action(for:)`, `SessionStore`, `applyHook`, `AggregateLight`, `aggregateLight`, `liveSessions`, `installedHooks`, `uninstalledHooks`, `HookInstaller` are used with consistent signatures across tasks and the app. ✓
