# Fat Traffic-Light Menu-Bar Icon + Enriched Dropdown — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single colored menu-bar dot with a fat traffic-light glyph whose active lamp signals aggregate status, and enrich the dropdown with an urgency-sorted session list plus a summary header.

**Architecture:** All decision/format logic lives as pure, unit-tested functions in `ClaudeLightCore` (`IconModel.swift`, `MenuModel.swift`). The app layer stays thin: a stateless `TrafficLightIcon` NSImage renderer, plus `SessionWatcher` driving an animation clock and publishing derived state. The menu-bar label and dropdown are SwiftUI views consuming that state.

**Tech Stack:** Swift 5.9, SwiftUI `MenuBarExtra(.menu)`, AppKit (`NSImage`, `NSBezierPath`), XCTest.

## Global Constraints

- swift-tools-version: 5.9; platform floor macOS 13 (`.v13`). Do not raise.
- Pure logic (no AppKit/SwiftUI imports) belongs in `ClaudeLightCore`; only `ClaudeLightCore` has a test target (`ClaudeLightCoreTests`).
- Swift strict concurrency: never reference a captured optional `var self` inside a concurrently-executing `Task` closure. Bind first: `guard let self else { return }` then `Task { @MainActor in self.method() }`. (The release runner's toolchain rejects the unbound form.)
- The menu-bar label image MUST be a non-template `NSImage` (`isTemplate = false`) — template coercion strips the lit lamp's color.
- Commit messages: Conventional Commits style. No AI attribution / co-author trailers.
- Run the full suite with `swift test`; build the app with `swift build`.
- Status→color: red = `.systemRed`-equivalent `srgb(1.00, 0.23, 0.19)`, orange = `srgb(1.00, 0.58, 0.00)`, green = `srgb(0.20, 0.78, 0.35)`.

## File Structure

- Create `Sources/ClaudeLightCore/IconModel.swift` — `IconLamp`, `IconState`, `iconState(for:)`, `litAlpha(for:phase:)`.
- Create `Sources/ClaudeLightCore/MenuModel.swift` — `StatusCounts`, `statusCounts(for:)`, `summaryText(for:)`, `sortedForMenu(_:)`, `relativeTime(secondsAgo:)`.
- Create `Tests/ClaudeLightCoreTests/IconModelTests.swift`, `Tests/ClaudeLightCoreTests/MenuModelTests.swift`.
- Create `Sources/ClaudeLightApp/TrafficLightIcon.swift` — NSImage renderer.
- Modify `Sources/ClaudeLightApp/SessionWatcher.swift` — animation clock, appearance, published derived state.
- Modify `Sources/ClaudeLightApp/ClaudeLightApp.swift` — label wiring; remove `dotImage`.
- Modify `Sources/ClaudeLightApp/MenuContent.swift` — summary header + enriched rows.

---

### Task 1: Core — IconLamp / IconState / iconState(for:)

**Files:**
- Create: `Sources/ClaudeLightCore/IconModel.swift`
- Test: `Tests/ClaudeLightCoreTests/IconModelTests.swift`

**Interfaces:**
- Consumes: `Session`, `SessionStatus` (from `Session.swift`).
- Produces:
  - `public enum IconLamp: String, Sendable, Equatable { case red, orange, green, off }`
  - `public struct IconState: Sendable, Equatable { let lamp: IconLamp; let blink: Bool; let breathe: Bool; init(lamp:blink:breathe:) }`
  - `public func iconState(for sessions: [Session]) -> IconState`

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeLightCoreTests/IconModelTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class IconModelTests: XCTestCase {
    private func s(_ status: SessionStatus) -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: "p", cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func test_empty_isOff() {
        XCTAssertEqual(iconState(for: []), IconState(lamp: .off, blink: false, breathe: false))
    }
    func test_allIdle_isGreenSteady() {
        XCTAssertEqual(iconState(for: [s(.idle), s(.idle)]), IconState(lamp: .green, blink: false, breathe: false))
    }
    func test_running_isOrangeBreathing() {
        XCTAssertEqual(iconState(for: [s(.idle), s(.running)]), IconState(lamp: .orange, blink: false, breathe: true))
    }
    func test_waitingOnly_isRedSteady() {
        XCTAssertEqual(iconState(for: [s(.waiting), s(.running)]), IconState(lamp: .red, blink: false, breathe: false))
    }
    func test_attention_isRedBlinking() {
        XCTAssertEqual(iconState(for: [s(.attention), s(.running)]), IconState(lamp: .red, blink: true, breathe: false))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IconModelTests`
Expected: FAIL — `cannot find 'iconState' in scope` / `cannot find 'IconState'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeLightCore/IconModel.swift`:

```swift
import Foundation

public enum IconLamp: String, Sendable, Equatable {
    case red, orange, green, off
}

public struct IconState: Sendable, Equatable {
    public let lamp: IconLamp
    public let blink: Bool
    public let breathe: Bool
    public init(lamp: IconLamp, blink: Bool, breathe: Bool) {
        self.lamp = lamp
        self.blink = blink
        self.breathe = breathe
    }
}

/// Aggregate lamp for the menu-bar icon. Priority: red (needs you) > orange
/// (working) > green (idle) > off (no live sessions). Pass the LIVE sessions.
public func iconState(for sessions: [Session]) -> IconState {
    if sessions.isEmpty {
        return IconState(lamp: .off, blink: false, breathe: false)
    }
    let hasAttention = sessions.contains { $0.status == .attention }
    let hasWaiting = sessions.contains { $0.status == .waiting }
    let hasRunning = sessions.contains { $0.status == .running }
    if hasWaiting || hasAttention {
        return IconState(lamp: .red, blink: hasAttention, breathe: false)
    }
    if hasRunning {
        return IconState(lamp: .orange, blink: false, breathe: true)
    }
    return IconState(lamp: .green, blink: false, breathe: false)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IconModelTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/IconModel.swift Tests/ClaudeLightCoreTests/IconModelTests.swift
git commit -m "feat: derive IconState (lamp + blink/breathe) from sessions"
```

---

### Task 2: Core — litAlpha(for:phase:)

**Files:**
- Modify: `Sources/ClaudeLightCore/IconModel.swift`
- Test: `Tests/ClaudeLightCoreTests/IconModelTests.swift`

**Interfaces:**
- Consumes: `IconState` (Task 1).
- Produces: `public func litAlpha(for state: IconState, phase: Double) -> Double` — alpha of the lit lamp at a given animation phase (seconds). Steady = 1.0; blink = 0.6s square wave (1.0 / 0.2); breathe = 1.5s cosine in 0.55…1.0.

- [ ] **Step 1: Write the failing test**

Append to `IconModelTests.swift`:

```swift
extension IconModelTests {
    private func steady() -> IconState { IconState(lamp: .green, blink: false, breathe: false) }
    private func blinking() -> IconState { IconState(lamp: .red, blink: true, breathe: false) }
    private func breathing() -> IconState { IconState(lamp: .orange, blink: false, breathe: true) }

    func test_litAlpha_steady_isFull() {
        XCTAssertEqual(litAlpha(for: steady(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: steady(), phase: 12.3), 1.0, accuracy: 0.0001)
    }
    func test_litAlpha_blink_squareWave() {
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.2), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.3), 0.2, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: blinking(), phase: 0.6), 1.0, accuracy: 0.0001) // wraps
    }
    func test_litAlpha_breathe_range() {
        XCTAssertEqual(litAlpha(for: breathing(), phase: 0.0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(litAlpha(for: breathing(), phase: 0.75), 0.55, accuracy: 0.0001) // half of 1.5
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter IconModelTests`
Expected: FAIL — `cannot find 'litAlpha' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/ClaudeLightCore/IconModel.swift`:

```swift
/// Alpha for the lit lamp at `phase` seconds. Pure so it is unit-testable;
/// the app advances `phase` via a timer.
public func litAlpha(for state: IconState, phase: Double) -> Double {
    if state.blink {
        let t = phase.truncatingRemainder(dividingBy: 0.6)
        return t < 0.3 ? 1.0 : 0.2
    }
    if state.breathe {
        let cycle = phase.truncatingRemainder(dividingBy: 1.5) / 1.5     // 0..1
        let c = cos(2 * Double.pi * cycle)                                // 1 → -1
        return 0.55 + 0.45 * (0.5 + 0.5 * c)                              // 1.0 … 0.55
    }
    return 1.0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter IconModelTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/IconModel.swift Tests/ClaudeLightCoreTests/IconModelTests.swift
git commit -m "feat: litAlpha blink/breathe animation curve"
```

---

### Task 3: Core — StatusCounts / statusCounts / summaryText

**Files:**
- Create: `Sources/ClaudeLightCore/MenuModel.swift`
- Test: `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Consumes: `Session`, `SessionStatus`.
- Produces:
  - `public struct StatusCounts: Sendable, Equatable { let needYou: Int; let working: Int; let idle: Int; init(needYou:working:idle:) }`
  - `public func statusCounts(for sessions: [Session]) -> StatusCounts` (`needYou` = waiting + attention).
  - `public func summaryText(for counts: StatusCounts) -> String?` (nil when all zero).

- [ ] **Step 1: Write the failing test**

Create `Tests/ClaudeLightCoreTests/MenuModelTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class MenuModelTests: XCTestCase {
    private func s(_ status: SessionStatus, project: String = "p") -> Session {
        Session(sessionID: UUID().uuidString, status: status, project: project, cwd: "/p",
                updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }

    func test_counts_bucketsWaitingAndAttentionTogether() {
        let c = statusCounts(for: [s(.waiting), s(.attention), s(.running), s(.idle), s(.idle)])
        XCTAssertEqual(c, StatusCounts(needYou: 2, working: 1, idle: 2))
    }
    func test_summary_nilWhenEmpty() {
        XCTAssertNil(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 0)))
    }
    func test_summary_singularNeedsYou() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 1, working: 0, idle: 0)), "1 needs you")
    }
    func test_summary_pluralAndWorking() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 2, working: 3, idle: 1)), "2 need you · 3 working")
    }
    func test_summary_idleOnly() {
        XCTAssertEqual(summaryText(for: StatusCounts(needYou: 0, working: 0, idle: 4)), "Idle")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuModelTests`
Expected: FAIL — `cannot find 'statusCounts' / 'summaryText' / 'StatusCounts'`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/ClaudeLightCore/MenuModel.swift`:

```swift
import Foundation

public struct StatusCounts: Sendable, Equatable {
    public let needYou: Int   // waiting + attention
    public let working: Int   // running
    public let idle: Int
    public init(needYou: Int, working: Int, idle: Int) {
        self.needYou = needYou
        self.working = working
        self.idle = idle
    }
}

public func statusCounts(for sessions: [Session]) -> StatusCounts {
    var needYou = 0, working = 0, idle = 0
    for session in sessions {
        switch session.status {
        case .waiting, .attention: needYou += 1
        case .running: working += 1
        case .idle: idle += 1
        }
    }
    return StatusCounts(needYou: needYou, working: working, idle: idle)
}

/// Words-and-counts summary for the dropdown header. nil = no live sessions.
public func summaryText(for counts: StatusCounts) -> String? {
    if counts.needYou == 0 && counts.working == 0 && counts.idle == 0 { return nil }
    var parts: [String] = []
    if counts.needYou > 0 {
        parts.append(counts.needYou == 1 ? "1 needs you" : "\(counts.needYou) need you")
    }
    if counts.working > 0 {
        parts.append("\(counts.working) working")
    }
    if parts.isEmpty { return "Idle" }   // only idle sessions
    return parts.joined(separator: " · ")
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuModelTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/MenuModel.swift Tests/ClaudeLightCoreTests/MenuModelTests.swift
git commit -m "feat: status counts + dropdown summary text"
```

---

### Task 4: Core — sortedForMenu

**Files:**
- Modify: `Sources/ClaudeLightCore/MenuModel.swift`
- Test: `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces: `public func sortedForMenu(_ sessions: [Session]) -> [Session]` — urgency order (attention, waiting, running, idle), ties broken by `project` ascending (stable display).

- [ ] **Step 1: Write the failing test**

Append to `MenuModelTests.swift`:

```swift
extension MenuModelTests {
    func test_sorted_urgencyThenProject() {
        let input = [
            s(.idle, project: "z"),
            s(.running, project: "b"),
            s(.attention, project: "m"),
            s(.running, project: "a"),
            s(.waiting, project: "k"),
        ]
        let order = sortedForMenu(input).map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["attention:m", "waiting:k", "running:a", "running:b", "idle:z"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuModelTests`
Expected: FAIL — `cannot find 'sortedForMenu' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/ClaudeLightCore/MenuModel.swift`:

```swift
/// Display order for the dropdown: most urgent first, then by project name
/// (stable so rows don't reorder as timestamps tick).
public func sortedForMenu(_ sessions: [Session]) -> [Session] {
    func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .attention: return 0
        case .waiting: return 1
        case .running: return 2
        case .idle: return 3
        }
    }
    return sessions.sorted { a, b in
        let ra = rank(a.status), rb = rank(b.status)
        if ra != rb { return ra < rb }
        return a.project < b.project
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuModelTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/MenuModel.swift Tests/ClaudeLightCoreTests/MenuModelTests.swift
git commit -m "feat: sort sessions by urgency for the dropdown"
```

---

### Task 5: Core — relativeTime

**Files:**
- Modify: `Sources/ClaudeLightCore/MenuModel.swift`
- Test: `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Produces: `public func relativeTime(secondsAgo: TimeInterval) -> String` — `"12s"`, `"2m"`, `"3h"`, `"2d"`; negatives clamp to `"0s"`.

- [ ] **Step 1: Write the failing test**

Append to `MenuModelTests.swift`:

```swift
extension MenuModelTests {
    func test_relativeTime_boundaries() {
        XCTAssertEqual(relativeTime(secondsAgo: -5), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 0), "0s")
        XCTAssertEqual(relativeTime(secondsAgo: 59), "59s")
        XCTAssertEqual(relativeTime(secondsAgo: 60), "1m")
        XCTAssertEqual(relativeTime(secondsAgo: 3599), "59m")
        XCTAssertEqual(relativeTime(secondsAgo: 3600), "1h")
        XCTAssertEqual(relativeTime(secondsAgo: 86399), "23h")
        XCTAssertEqual(relativeTime(secondsAgo: 86400), "1d")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MenuModelTests`
Expected: FAIL — `cannot find 'relativeTime' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/ClaudeLightCore/MenuModel.swift`:

```swift
/// Compact relative-age label for a session row.
public func relativeTime(secondsAgo: TimeInterval) -> String {
    let s = max(0, Int(secondsAgo))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    if h < 24 { return "\(h)h" }
    return "\(h / 24)d"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MenuModelTests`
Expected: PASS (7 tests). Then run the full suite: `swift test` → all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/MenuModel.swift Tests/ClaudeLightCoreTests/MenuModelTests.swift
git commit -m "feat: relative-time labels for session rows"
```

---

### Task 6: App — TrafficLightIcon renderer

**Files:**
- Create: `Sources/ClaudeLightApp/TrafficLightIcon.swift`

**Interfaces:**
- Consumes: `IconLamp` (Task 1).
- Produces: `enum TrafficLightIcon { static let size: NSSize; static func image(lamp: IconLamp, litAlpha: CGFloat, mono: NSColor) -> NSImage }` — fat outline housing + three squared rectangular bar lamps; the lit bar in its state color at `litAlpha`, others `mono` at 0.28. Non-template.

> No unit test (app target has no test target). Verified by build + manual run in Task 9's checkpoint.

- [ ] **Step 1: Create the renderer**

Create `Sources/ClaudeLightApp/TrafficLightIcon.swift`:

```swift
import AppKit
import ClaudeLightCore

/// Draws the fat traffic-light menu-bar glyph: a rounded-rectangle outline
/// housing with three squared bar lamps. Exactly one bar is lit; the rest are
/// dimmed `mono`. Non-template so the lit color survives in the menu bar.
enum TrafficLightIcon {
    /// Fixed glyph size in points (fat aspect, fits the ~18pt menu-bar height).
    static let size = NSSize(width: 15, height: 18)

    static func image(lamp: IconLamp, litAlpha: CGFloat, mono: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()

        let stroke: CGFloat = 1.6
        let housing = NSRect(origin: .zero, size: size).insetBy(dx: stroke/2 + 0.5, dy: stroke/2 + 0.5)
        let radius = housing.width * 0.30
        let outline = NSBezierPath(roundedRect: housing, xRadius: radius, yRadius: radius)
        outline.lineWidth = stroke
        mono.setStroke()
        outline.stroke()

        let lamps: [IconLamp] = [.red, .orange, .green]   // top → bottom
        let innerTop = housing.maxY - housing.width * 0.20
        let innerBot = housing.minY + housing.width * 0.20
        let span = innerTop - innerBot
        let centers = [innerTop, (innerTop + innerBot) / 2, innerBot]
        let barW = housing.width * 0.60
        let barH = span / 3 * 0.78
        let barR = barH * 0.22

        for i in 0..<3 {
            let rect = NSRect(x: housing.midX - barW/2, y: centers[i] - barH/2, width: barW, height: barH)
            let isLit = lamps[i] == lamp
            let fill = isLit ? litColor(lamps[i]).withAlphaComponent(litAlpha)
                             : mono.withAlphaComponent(0.28)
            fill.setFill()
            NSBezierPath(roundedRect: rect, xRadius: barR, yRadius: barR).fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func litColor(_ lamp: IconLamp) -> NSColor {
        switch lamp {
        case .red:    return NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1)
        case .green:  return NSColor(srgbRed: 0.20, green: 0.78, blue: 0.35, alpha: 1)
        case .off:    return .clear
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!` (renderer compiles; not yet wired in).

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/TrafficLightIcon.swift
git commit -m "feat: fat traffic-light NSImage renderer"
```

---

### Task 7: App — SessionWatcher animation clock, appearance, derived state

**Files:**
- Modify: `Sources/ClaudeLightApp/SessionWatcher.swift` (full replacement below)

**Interfaces:**
- Consumes: `iconState`, `litAlpha` indirectly, `sortedForMenu`, `statusCounts`, `summaryText`, `liveSessions` (Core).
- Produces (published, read by the app/dropdown): `sessions: [Session]` (now urgency-sorted), `icon: IconState`, `summary: String?`, `animationPhase: Double`, `isDarkMenuBar: Bool`, plus existing `hooksInstalled`, `installHooks()`, `removeHooks()`, `start()`. Removes `light`, `needsAttention`, `attentionPhase`.

> Verified by build now; visual behavior verified at Task 9 checkpoint.

- [ ] **Step 1: Replace the file**

Replace the entire contents of `Sources/ClaudeLightApp/SessionWatcher.swift` with:

```swift
import Foundation
import Combine
import CoreServices
import AppKit
import ClaudeLightCore

@MainActor
final class SessionWatcher: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var hooksInstalled: Bool = false
    @Published private(set) var icon: IconState = IconState(lamp: .off, blink: false, breathe: false)
    @Published private(set) var summary: String? = nil
    @Published private(set) var animationPhase: Double = 0
    @Published private(set) var isDarkMenuBar: Bool = true

    private let store: SessionStore
    private let installer: HookInstaller
    private var stream: FSEventStreamRef?
    private var staleTimer: Timer?
    private var clockTimer: Timer?
    private var started = false
    private let clockInterval: TimeInterval = 0.08

    init(store: SessionStore, installer: HookInstaller) {
        self.store = store
        self.installer = installer
    }

    /// Call exactly once. Idempotent: subsequent calls are no-ops.
    func start() {
        guard !started else { return }
        started = true
        hooksInstalled = installer.isInstalled()
        updateAppearance()
        observeAppearance()
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        reload()
        startFSEvents()
        staleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.reload() }
        }
    }

    func installHooks() {
        try? installer.install()
        hooksInstalled = installer.isInstalled()
    }

    func removeHooks() {
        try? installer.uninstall()
        hooksInstalled = installer.isInstalled()
    }

    func reload() {
        let all = (try? store.loadAll()) ?? []
        let live = sortedForMenu(liveSessions(all, now: Date()))
        self.sessions = live
        let state = iconState(for: live)
        self.icon = state
        self.summary = summaryText(for: statusCounts(for: live))
        updateClock(animating: state.blink || state.breathe)
    }

    /// Runs the animation clock only while a lamp is blinking or breathing.
    private func updateClock(animating: Bool) {
        if animating {
            guard clockTimer == nil else { return }
            clockTimer = Timer.scheduledTimer(withTimeInterval: clockInterval, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.animationPhase += self.clockInterval }
            }
        } else {
            clockTimer?.invalidate()
            clockTimer = nil
            animationPhase = 0
        }
    }

    // MARK: - Menu-bar appearance (for the adaptive mono color)

    private func updateAppearance() {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        isDarkMenuBar = (match == .darkAqua)
    }

    private func observeAppearance() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateAppearance() }
        }
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
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }
}
```

> Note: if the original `startFSEvents()` body differs (e.g., flag constants), keep the original body verbatim — only the published properties, `reload()`, the clock, and appearance methods are new. The block above reproduces the established FSEvents pattern.

- [ ] **Step 2: Verify it builds (expect downstream breakage)**

Run: `swift build`
Expected: FAIL — `ClaudeLightApp.swift` and possibly `MenuContent.swift` reference removed members (`watcher.light`, `needsAttention`, `attentionPhase`, `dotImage`). That is fixed in Tasks 8–9. (If it builds clean, even better.)

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/SessionWatcher.swift
git commit -m "feat: SessionWatcher publishes icon state + animation clock + appearance"
```

---

### Task 8: App — wire the menu-bar label to the renderer

**Files:**
- Modify: `Sources/ClaudeLightApp/ClaudeLightApp.swift`

**Interfaces:**
- Consumes: `watcher.icon`, `watcher.animationPhase`, `watcher.isDarkMenuBar`, `litAlpha(for:phase:)`, `TrafficLightIcon.image(lamp:litAlpha:mono:)`.

- [ ] **Step 1: Replace the label and delete `dotImage`**

In `Sources/ClaudeLightApp/ClaudeLightApp.swift`, replace the `label:` closure body:

```swift
        } label: {
            Image(nsImage: TrafficLightIcon.image(
                lamp: watcher.icon.lamp,
                litAlpha: CGFloat(litAlpha(for: watcher.icon, phase: watcher.animationPhase)),
                mono: watcher.isDarkMenuBar ? .white : .black))
                .onAppear {
                    watcher.start()
                    DispatchQueue.main.async { offerHookInstallIfNeeded() }
                }
        }
        .menuBarExtraStyle(.menu)
```

Then **delete** the entire `private static func dotImage(for:dim:) -> NSImage { … }` method (it is no longer referenced). Leave `offerHookInstallIfNeeded()` unchanged.

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!` (label compiles against the new published members).

- [ ] **Step 3: Commit**

```bash
git add Sources/ClaudeLightApp/ClaudeLightApp.swift
git commit -m "feat: render fat traffic-light icon in the menu bar"
```

---

### Task 9: App — enrich the dropdown

**Files:**
- Modify: `Sources/ClaudeLightApp/MenuContent.swift` (full replacement below)

**Interfaces:**
- Consumes: `watcher.sessions` (sorted), `watcher.summary`, `watcher.icon`, `relativeTime(secondsAgo:)`, `watcher.hooksInstalled`, `installHooks()`, `removeHooks()`.

- [ ] **Step 1: Replace the file**

Replace the entire contents of `Sources/ClaudeLightApp/MenuContent.swift` with:

```swift
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
```

- [ ] **Step 2: Verify it builds and the suite passes**

Run: `swift build && swift test`
Expected: `Build complete!` and all tests pass (66 existing + new IconModel/MenuModel tests).

- [ ] **Step 3: Manual verification (visual checkpoint)**

Run: `bash scripts/package-app.sh && open "dist/Claude Light.app"`
Confirm in the menu bar and dropdown:
- No sessions → all three bars dim (no lamp lit); dropdown shows "No active Claude Code sessions".
- Trigger a Claude Code session (or hand-write a session JSON in `SessionStore.defaultDirectory()`) so a `running` session exists → middle (orange) bar lit and gently breathing; dropdown header "1 working", row `project — running · Ns`.
- A session `awaiting your reply` (`attention`) → top (red) bar lit and blinking; header "1 needs you".
- Toggle System Settings → Appearance between Light/Dark → housing/dim bars flip black/white and stay legible.

- [ ] **Step 4: Commit**

```bash
git add Sources/ClaudeLightApp/MenuContent.swift
git commit -m "feat: dropdown summary header + urgency-sorted rows with activity time"
```

---

## Self-Review

**Spec coverage:**
- Icon lamp selection / off state → Task 1. ✔
- Motion (blink/breathe curve) → Task 2 (curve) + Task 8 (applied). ✔
- Fat rectangular-bar rendering + adaptive mono → Task 6 (render) + Task 7 (isDark) + Task 8 (mono wiring). ✔
- Summary header words+counts → Task 3 + Task 9. ✔
- Urgency-sorted flat list → Task 4 + Task 9. ✔
- Relative time → Task 5 + Task 9. ✔
- Empty state + actions → Task 9. ✔
- Animation clock runs only while animating; appearance re-render → Task 7. ✔
- Fixed-width icon (constant `TrafficLightIcon.size`) → Task 6. ✔

**Placeholder scan:** none — every code/test step has complete content.

**Type consistency:** `IconState(lamp:blink:breathe:)`, `iconState(for:)`, `litAlpha(for:phase:)`, `StatusCounts(needYou:working:idle:)`, `statusCounts(for:)`, `summaryText(for:)`, `sortedForMenu(_:)`, `relativeTime(secondsAgo:)`, `TrafficLightIcon.image(lamp:litAlpha:mono:)`, and `SessionWatcher` published `icon`/`summary`/`animationPhase`/`isDarkMenuBar` are used identically across tasks.
