# Handoff Session State Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `handoff` session state — turn ended with a prose-inferred review/approval ask — shown as steady red in the menu-bar icon and a red "review requested" row in the dropdown.

**Architecture:** A new `SessionStatus` case flows through the existing pure-function pipeline: detection on `Stop` in `HookAction` (via a new `textEndsWithHandoffAsk` in `HandoffDetection.swift`), aggregation in `Aggregate.swift`/`IconModel.swift`, display mapping in `MenuModel.swift` (core) and `MenuContent.swift` (app). The existing attention heuristic (`textEndsWithQuestion`, PR #33 tuning) is not modified.

**Tech Stack:** Swift Package Manager, XCTest. Core logic lives in `ClaudeLightCore` (pure, fully tested); AppKit/SwiftUI display in `ClaudeLightApp` (compile-checked, not unit-tested).

**Spec:** `docs/superpowers/specs/2026-07-02-handoff-state-design.md`

## Global Constraints

- Branch: `feat/handoff-state` (already created). Never commit to `main`.
- Commit messages: conventional style (`feat:`, `docs:`), **no AI attribution trailers or footers of any kind**.
- `textEndsWithQuestion` and its tuning (`questionMaxLength = 240`) stay byte-for-byte unchanged in behavior; the only permitted edit is widening `private` → internal (module) visibility so `HandoffDetection.swift` can reuse `strippingCode` and `questionMaxLength`.
- All core logic as pure functions in `Sources/ClaudeLightCore`, tests in `Tests/ClaudeLightCoreTests`, XCTest, no new dependencies.
- Test command: `swift test` (filtered per task); app target must also build: `swift build`.
- New enum raw value is exactly `"handoff"`; dropdown label is exactly `review requested`.

---

### Task 1: `handoff` state in the model + dropdown row

Adding a case to `SessionStatus` breaks four exhaustive switches (`statusCounts`, `sortedForMenu`'s `rank`, and the app's `color(for:)` / `friendlyLabel`), so the enum case and those switches are one compile-coupled task.

**Files:**
- Modify: `Sources/ClaudeLightCore/Session.swift:3-9`
- Modify: `Sources/ClaudeLightCore/MenuModel.swift` (`statusCounts`, `sortedForMenu`)
- Modify: `Sources/ClaudeLightApp/MenuContent.swift:161-177` (`color(for:)`, `friendlyLabel`)
- Test: `Tests/ClaudeLightCoreTests/SessionTests.swift`
- Test: `Tests/ClaudeLightCoreTests/MenuModelTests.swift`

**Interfaces:**
- Consumes: existing `SessionStatus`, `StatusCounts`, `sortedForMenu`.
- Produces: `SessionStatus.handoff` (raw value `"handoff"`) — every later task references this case. Sort rank order: `error(0), attention(1), waiting(2), handoff(3), running(4), idle(5)`. Counts: handoff increments `needYou`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeLightCoreTests/SessionTests.swift` (inside `final class SessionTests`):

```swift
    func test_handoffStatus_roundTrips_throughJSON() throws {
        let s = Session(sessionID: "h1", status: .handoff, project: "p", cwd: "/p",
                        updatedAt: Date(timeIntervalSince1970: 1000))
        let data = try ClaudeLightJSON.encoder.encode(s)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"status\":\"handoff\""))
        XCTAssertEqual(try ClaudeLightJSON.decoder.decode(Session.self, from: data), s)
    }
```

Append to `Tests/ClaudeLightCoreTests/MenuModelTests.swift` (inside the `extension MenuModelTests`):

```swift
    func test_counts_handoffFoldsIntoNeedYou() {
        let c = statusCounts(for: [s(.handoff), s(.waiting), s(.running)])
        XCTAssertEqual(c, StatusCounts(needYou: 2, working: 1, idle: 0, error: 0))
    }

    func test_sorted_handoffBetweenWaitingAndRunning() {
        let input = [
            s(.running, project: "r"),
            s(.handoff, project: "h"),
            s(.idle, project: "z"),
            s(.waiting, project: "w"),
        ]
        let order = sortedForMenu(input).map { "\($0.status.rawValue):\($0.project)" }
        XCTAssertEqual(order, ["waiting:w", "handoff:h", "running:r", "idle:z"])
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'SessionTests|MenuModelTests'`
Expected: **compile error** — `type 'SessionStatus' has no member 'handoff'`. (A compile failure is the failing state here; it proves the tests exercise the new case.)

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/Session.swift` — add the case after `attention`:

```swift
public enum SessionStatus: String, Codable, Sendable {
    case running
    case waiting
    case attention
    case handoff
    case idle
    case error
}
```

`Sources/ClaudeLightCore/MenuModel.swift` — update the `StatusCounts` doc line and the two switches:

```swift
    public let needYou: Int   // waiting + attention + handoff
```

```swift
        switch session.status {
        case .waiting, .attention, .handoff: needYou += 1
        case .running: working += 1
        case .idle: idle += 1
        case .error: error += 1
        }
```

```swift
    func rank(_ status: SessionStatus) -> Int {
        switch status {
        case .error: return 0
        case .attention: return 1
        case .waiting: return 2
        case .handoff: return 3
        case .running: return 4
        case .idle: return 5
        }
    }
```

`Sources/ClaudeLightApp/MenuContent.swift` — update both switches:

```swift
    private func color(for status: SessionStatus) -> NSColor {
        switch status {
        case .waiting, .attention, .handoff, .error: return Self.red
        case .running: return Self.orange
        case .idle: return Self.green
        }
    }
```

```swift
    private func friendlyLabel(for status: SessionStatus) -> String {
        switch status {
        case .running: return "running"
        case .waiting: return "waiting for permission"
        case .attention: return "awaiting your reply"
        case .handoff: return "review requested"
        case .idle: return "idle"
        case .error: return "API error"
        }
    }
```

- [ ] **Step 4: Run tests and build to verify green**

Run: `swift test --filter 'SessionTests|MenuModelTests'`
Expected: PASS (all, including pre-existing tests).
Run: `swift build`
Expected: `Build complete!` (proves the app target's switches are exhaustive again).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Session.swift Sources/ClaudeLightCore/MenuModel.swift Sources/ClaudeLightApp/MenuContent.swift Tests/ClaudeLightCoreTests/SessionTests.swift Tests/ClaudeLightCoreTests/MenuModelTests.swift
git commit -m "feat: add handoff session status with review-requested row"
```

---

### Task 2: Handoff detection heuristic

**Files:**
- Create: `Sources/ClaudeLightCore/HandoffDetection.swift`
- Modify: `Sources/ClaudeLightCore/QuestionDetection.swift:17,21` (visibility only: drop `private` from `questionMaxLength` and `strippingCode`)
- Test: `Tests/ClaudeLightCoreTests/HandoffDetectionTests.swift`

**Interfaces:**
- Consumes: `strippingCode(_ s: String) -> String` and `questionMaxLength: Int` from `QuestionDetection.swift` (after widening to internal).
- Produces: `public func textEndsWithHandoffAsk(_ text: String) -> Bool` — Task 3 calls this.

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeLightCoreTests/HandoffDetectionTests.swift`:

```swift
import XCTest
@testable import ClaudeLightCore

final class HandoffDetectionTests: XCTestCase {

    // The motivating case: a long deliverable turn ending in an approval ask,
    // no question mark anywhere.
    private let motivatingTurn = """
    The five surfaces are covered and the spec documents the three decisions \
    taken while you were away.

    Spec is at docs/specs/design.md and the branch is created and ready.

    Please review — especially the three flagged decisions — and if it looks \
    right I'll move on to the implementation plan.
    """

    func test_true_approvalPhraseInTrailingParagraph() {
        XCTAssertTrue(textEndsWithHandoffAsk(motivatingTurn))
    }

    func test_true_longTurnWhoseTrailingParagraphEndsWithQuestionMark() {
        let long = String(repeating: "Here is a chunk of the summary. ", count: 12)
            + "\n\nShould I use approach A or B for the migration?"
        XCTAssertTrue(textEndsWithHandoffAsk(long))
    }

    func test_true_caseInsensitivePhrase() {
        XCTAssertTrue(textEndsWithHandoffAsk("Work is done.\n\nPLEASE REVIEW the spec."))
    }

    func test_false_questionMarkOnlyInsideCode() {
        XCTAssertFalse(textEndsWithHandoffAsk("Here is the fix:\n\n```\nx = a ? b : c\nprint(y?)\n```"))
    }

    func test_false_trailingParagraphTooLong() {
        let bloated = "Intro paragraph.\n\n"
            + String(repeating: "please review this endless wall of text ", count: 10) + "?"
        XCTAssertFalse(textEndsWithHandoffAsk(bloated))
    }

    func test_false_plainCompletion() {
        XCTAssertFalse(textEndsWithHandoffAsk("All 131 tests pass."))
    }

    func test_false_empty() {
        XCTAssertFalse(textEndsWithHandoffAsk(""))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HandoffDetectionTests`
Expected: **compile error** — `cannot find 'textEndsWithHandoffAsk' in scope`.

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/QuestionDetection.swift` — visibility only (no logic change):

```swift
/// Upper bound (characters) for treating a turn as a pending question. Tunable.
let questionMaxLength = 240
```

```swift
/// Remove fenced ```code``` blocks and `inline` code spans so a `?` inside code
/// isn't mistaken for a question.
func strippingCode(_ s: String) -> String {
```

Create `Sources/ClaudeLightCore/HandoffDetection.swift`:

```swift
import Foundation

/// Heuristic: the turn ended by handing the user a work item — a review,
/// approval, or sign-off ask — rather than a direct blocking question.
/// Evaluated on Stop only after `textEndsWithQuestion` declined, so the
/// attention heuristic keeps first claim on concise questions.
///
/// We look at the LAST prose paragraph (code stripped): a concise closer that
/// ends with `?` or contains an approval-ask phrase reads as "your move".
public func textEndsWithHandoffAsk(_ text: String) -> Bool {
    let paragraphs = strippingCode(text)
        .components(separatedBy: "\n\n")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard let closer = paragraphs.last, closer.count <= questionMaxLength else { return false }
    if closer.hasSuffix("?") { return true }
    let lowered = closer.lowercased()
    return handoffAskPhrases.contains { lowered.contains($0) }
}

/// Phrases that mark a closer as an approval ask. Tunable, like `questionMaxLength`.
private let handoffAskPhrases = [
    "please review", "let me know", "sign off", "sign-off", "approve",
    "should i proceed", "if it looks right", "if it looks good", "waiting for your",
]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'HandoffDetectionTests|QuestionDetectionTests'`
Expected: PASS — including all pre-existing `QuestionDetectionTests` (visibility change must not alter behavior).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/HandoffDetection.swift Sources/ClaudeLightCore/QuestionDetection.swift Tests/ClaudeLightCoreTests/HandoffDetectionTests.swift
git commit -m "feat: detect review/approval asks in a turn's closing paragraph"
```

---

### Task 3: Wire handoff into the Stop hook

**Files:**
- Modify: `Sources/ClaudeLightCore/HookAction.swift:13-17`
- Test: `Tests/ClaudeLightCoreTests/HookActionTests.swift`

**Interfaces:**
- Consumes: `textEndsWithHandoffAsk(_:)` (Task 2), `SessionStatus.handoff` (Task 1).
- Produces: `action(for:transcriptJSONL:)` now returns `.set(.handoff)` for approval-prose Stops. Downstream (store/app) needs no changes — `Session.status` already carries any `SessionStatus`.

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeLightCoreTests/HookActionTests.swift` (inside the class):

```swift
    func test_stop_approvalProseTranscript_isHandoff() {
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Spec is written on the branch.\n\nPlease review — and if it looks right I'll move on to the implementation plan."}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.handoff))
    }

    func test_stop_conciseQuestion_attentionWinsOverHandoff() {
        // Ends with "?" AND contains an approval phrase; concise → attention keeps first claim.
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Let me know — should I proceed?"}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.attention))
    }

    func test_stop_longTurnEndingInQuestionParagraph_isHandoff() {
        let text = String(repeating: "Here is a chunk of the summary. ", count: 12)
            + "\\n\\nShould I use approach A or B?"
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""# + text + #""}]}}"#
        XCTAssertEqual(action(for: payload("Stop"), transcriptJSONL: jsonl), .set(.handoff))
    }
```

Note on the third test: the fixture builds the JSON line by string concatenation and the paragraph break must be an **escaped** `\n\n` inside the JSON string (hence `\\n\\n` in the Swift literal, which is NOT inside a `#"..."#` segment).

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HookActionTests`
Expected: FAIL — the two new handoff tests return `.set(.idle)`; the attention-precedence test already passes (guards the invariant).

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/HookAction.swift` — replace the `Stop` branch:

```swift
    case "Stop":
        if let t = transcriptJSONL, let last = lastAssistantText(transcriptJSONL: t) {
            if textEndsWithQuestion(last) { return .set(.attention) }
            if textEndsWithHandoffAsk(last) { return .set(.handoff) }
        }
        return .set(.idle)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'HookActionTests|ApplyHookTests'`
Expected: PASS (ApplyHook consumes `action(for:)`; its existing tests must stay green).

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/HookAction.swift Tests/ClaudeLightCoreTests/HookActionTests.swift
git commit -m "feat: set handoff status when a Stop turn closes with a review ask"
```

---

### Task 4: Steady-red icon and aggregate

**Files:**
- Modify: `Sources/ClaudeLightCore/Aggregate.swift:17-25`
- Modify: `Sources/ClaudeLightCore/IconModel.swift:24-38`
- Test: `Tests/ClaudeLightCoreTests/AggregateTests.swift`
- Test: `Tests/ClaudeLightCoreTests/IconModelTests.swift`

**Interfaces:**
- Consumes: `SessionStatus.handoff` (Task 1).
- Produces: `aggregateLight` → `.red` for handoff; `iconState` lights red `.steady` (never `.blink`) for handoff, suppressing orange and green; `aggregateNeedsAttention` unchanged (attention-only).

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeLightCoreTests/AggregateTests.swift` (inside the class):

```swift
    func test_handoffSession_isRedButNotNeedsAttention() {
        XCTAssertEqual(aggregateLight(for: [s(.handoff)]), .red)
        XCTAssertFalse(aggregateNeedsAttention([s(.handoff)]))
    }
```

Append to `Tests/ClaudeLightCoreTests/IconModelTests.swift` (inside the class):

```swift
    func test_handoffOnly_redSteady() {
        XCTAssertEqual(iconState(for: [s(.handoff)]), st(.steady, .off, .off))
    }
    func test_handoffRunning_redSteady_orangeSuppressed() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.running)]), st(.steady, .off, .off))
    }
    func test_handoffIdle_redSteady_greenSuppressed() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.idle)]), st(.steady, .off, .off))
    }
    func test_handoffAttention_redBlinkWins() {
        XCTAssertEqual(iconState(for: [s(.handoff), s(.attention)]), st(.blink, .off, .off))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter 'AggregateTests|IconModelTests'`
Expected: FAIL — handoff sessions currently produce `.green` aggregate and all-off/green icon.

- [ ] **Step 3: Implement**

`Sources/ClaudeLightCore/Aggregate.swift` — one line changes:

```swift
public func aggregateLight(for sessions: [Session]) -> AggregateLight {
    if sessions.contains(where: { $0.status == .waiting || $0.status == .attention || $0.status == .handoff }) { return .red }
    if sessions.contains(where: { $0.status == .running }) { return .orange }
    return .green
}
```

`Sources/ClaudeLightCore/IconModel.swift` — replace the body of `iconState(for:)` and update the doc comment:

```swift
/// Model B: today's single aggregate lamp (red > orange > green) with `error`
/// layered on additively as a blinking red that does NOT suppress the base.
/// Handoff (review requested) is a base-red like waiting: steady, never blink.
public func iconState(for sessions: [Session]) -> IconState {
    let hasError = sessions.contains { $0.status == .error }
    let hasAttention = sessions.contains { $0.status == .attention }
    let hasWaiting = sessions.contains { $0.status == .waiting }
    let hasHandoff = sessions.contains { $0.status == .handoff }
    let hasRunning = sessions.contains { $0.status == .running }
    let hasIdle = sessions.contains { $0.status == .idle }

    let baseRed = hasWaiting || hasHandoff
    let red: LampMotion = (hasError || hasAttention) ? .blink : (baseRed ? .steady : .off)
    // Orange is suppressed by a base-red (waiting/handoff/attention) but NOT by error.
    let orange: LampMotion = (hasRunning && !baseRed && !hasAttention) ? .breathe : .off
    // Green only when nothing else is active at all.
    let green: LampMotion = (hasIdle && !hasError && !hasRunning && !baseRed && !hasAttention) ? .steady : .off

    return IconState(red: red, orange: orange, green: green)
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter 'AggregateTests|IconModelTests'`
Expected: PASS, including all pre-existing cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeLightCore/Aggregate.swift Sources/ClaudeLightCore/IconModel.swift Tests/ClaudeLightCoreTests/AggregateTests.swift Tests/ClaudeLightCoreTests/IconModelTests.swift
git commit -m "feat: light steady red for handoff in aggregate and icon"
```

---

### Task 5: Full verification + README

**Files:**
- Modify: `README.md:31` (red-lamp row of the states table)
- Test: full suite

**Interfaces:**
- Consumes: everything above.
- Produces: shippable branch.

- [ ] **Step 1: Update README**

In the states table, extend the red-lamp description (line 31) from:

```markdown
| <img src="assets/lamp-red.svg" width="22" alt=""> Top — red | A session needs you: a question or permission prompt is waiting | Blinks |
```

to:

```markdown
| <img src="assets/lamp-red.svg" width="22" alt=""> Top — red | A session needs you: a question, permission prompt, or review request is waiting | Blinks |
```

- [ ] **Step 2: Run the full suite and build**

Run: `swift test`
Expected: PASS — 0 failures (131 tests before this feature, 18 added by Tasks 1–4).
Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: mention review requests in the red-lamp description"
```

---

## Out of scope (per spec)

- Investigating Claude Code's 60s idle `Notification` as a complementary signal.
- Any change to the attention heuristic, TTL, version bump, or cask/release process.
