# Design — Session liveness (API-error detection) + concurrent traffic light

Date: 2026-07-01
Status: Approved (pending spec review)

## Goal

Make the menu-bar light trustworthy when a Claude Code session fails or when
several sessions are in different states at once. Two coupled changes:

1. **API-error detection** — when a running session hits an API/connection error,
   Claude Code writes a synthetic `"API Error: …"` message to its transcript but
   fires no status hook, so today the light stays stuck on orange ("working") for
   up to the 30-minute TTL. Detect that trailing error from the transcript and
   surface the session as **error** (red).
2. **Error as an additive lamp** — keep today's single **aggregate** lamp for the
   normal states (most-urgent wins: red > orange > green), and layer the error
   signal on top as an *additional* blinking red. So a failure never blacks out the
   rest — `error + running` shows orange breathing **and** red blinking — but normal
   states stay a single lamp, exactly as shipped. (This is model "B"; the fully
   complementary model — two lamps for every red+running combo — was considered and
   rejected as busier and off-metaphor.)

Non-goal / explicitly dropped: a "heartbeat" that stops the orange animation after
a quiet period. It cannot distinguish a genuinely long tool call (a 20-minute build
writes nothing) from a dead session, so it would mislabel long tasks. Orange
breathes for the entire duration a session is running.

## Background (verified)

- Claude Code records API errors in the per-session transcript
  `~/.claude/projects/<slug>/<session-id>.jsonl` as a synthetic assistant message:
  `type: assistant`, `message.model: "<synthetic>"`, and `message.content[].text`
  begins with `"API Error: …"` (observed: `"API Error: Unable to connect to API
  (ConnectionRefused)"`, `"API Error: Connection closed mid-response…"`).
- The hook payload already carries `transcriptPath` (`HookPayload.transcriptPath`),
  and the app already parses transcripts (`QuestionDetection.lastAssistantText`) to
  drive the blink-on-question feature. This design extends that existing mechanism.
- `liveSessions(_:now:ttl:)` drops sessions older than 30 minutes (unchanged here).

## Current state

- `SessionStatus`: `running | waiting | attention | idle`.
- `iconState(for:) -> IconState` returns a **single** `IconLamp` (`red/orange/green/off`)
  plus `blink`/`breathe` bools. Red for waiting/attention (blink only on attention),
  orange for running (breathe), green for idle, off for no sessions.
- `TrafficLightIcon.image(lamp:litAlpha:mono:)` lights exactly one bar.
- Dropdown rows: `project — <friendly status> · <relativeTime>`, urgency-sorted,
  with a summary header and colored dots.

## Design

### 1. Lamp rules — aggregate base + error overlay (model B)

Two ingredients:

- **Base aggregate** (unchanged from today, most-urgent wins across the normal
  states): red for `waiting`/`attention` > orange for `running` > green for `idle`.
- **Error overlay**: if any session has errored, the red lamp **blinks** — *in
  addition to* whatever the base shows. Error is layered on; it does **not**
  participate in the base suppression hierarchy.

Resolved per lamp (input: live sessions with the `.error` overlay already applied):

| Lamp | Motion |
|------|--------|
| Red | **blink** if any `error` or `attention`; else **steady** if any `waiting`; else `off` |
| Orange | **breathe** if any `running` **and** no `waiting`/`attention`; else `off` |
| Green | **steady** if any `idle` **and** nothing else active (no `error`/`running`/`waiting`/`attention`); else `off` |
| (all dim) | no live sessions |

The pivotal distinction: `waiting`/`attention` suppress orange (base aggregate is
red > orange), but **error does not** — it is additive. So an error can coexist with
the base lamp, while a permission-wait cannot.

| Sessions | Icon |
|----------|------|
| running only | orange breathe |
| waiting + running | red steady — single lamp, **as today** |
| attention + running | red blink — **as today** |
| **error + running** | **orange breathe + red blink** (two lamps) |
| error only | red blink |
| error + idle | red blink (green suppressed — error is active) |
| idle only | green steady |
| none | dim |

Edge case: if a permission-wait also pushes the base to red (`error + waiting +
running`), the icon shows a single blinking red and orange is hidden — acceptable.

### 2. Error detection

A running session is reclassified as **error** when the *latest substantive turn*
in its transcript is a synthetic `"API Error: …"` message.

- `public func apiErrorReason(transcriptJSONL: String) -> String?`
  - Scans lines bottom-up (mirrors `QuestionDetection.lastAssistantText`).
  - Considers only *substantive* entries — assistant messages (real or synthetic)
    and user messages; skips `system`, `hook_success`, `task_reminder`, tool
    plumbing, etc.
  - If the first substantive entry from the bottom is an assistant message with
    `model == "<synthetic>"` and text starting `"API Error:"`, returns a short
    reason (text after `"API Error:"`, trimmed and shortened — e.g.
    `"Unable to connect to API (ConnectionRefused)"` → `"connection refused"`;
    `"Connection closed mid-response…"` → `"connection closed"`). See Reason
    normalization below.
  - If a newer real user/assistant message follows the error (recovered), or there
    is no error, returns `nil`.
- **Self-healing:** the overlay is recomputed on every refresh; when the session
  recovers or ends, `apiErrorReason` returns `nil` and the session leaves `error`
  with no manual dismissal. Detection latency ≤ the 30-second refresh cadence.

**Reason normalization** (`apiErrorReason` returns the display reason directly):
lower-case the text after `"API Error:"`; map known phrasings to a short form —
contains `"connectionrefused"`/`"unable to connect"` → `"connection refused"`;
contains `"connection closed"` → `"connection closed"`; otherwise the first ~40
chars of the message, trimmed. Never returns an empty string (fall back to
`"api error"`).

### 3. Data model & flow

- **`Session`** gains `public var transcriptPath: String?` (Codable key
  `transcript_path`). The hook shim writes it from `HookPayload.transcriptPath`.
  Backward-compatible: decoding an older session file without the key yields `nil`.
- **`SessionStatus`** gains `case error`. It is a **display overlay**, not a hook
  state: the hook keeps persisting `running`; the watcher rewrites a live `running`
  session to `.error` in the in-memory list when `apiErrorReason` is non-nil. The
  error reason travels alongside for the dropdown (see below).
- **Watcher** (`SessionWatcher.reload`), each refresh: for every live session that
  is `running` and has a `transcriptPath`, do a **bounded tail-read** of the
  transcript (last ~64 KB, whole file if smaller) and call `apiErrorReason`. If
  non-nil, overlay `.error` and stash the reason. Cheap: one bounded read per
  running session, every 30 s (plus on hook-driven reloads).

Because the error carries a reason string for display, the watcher produces a small
view type rather than only `[Session]`:

```swift
public struct SessionRow: Sendable, Equatable {   // ClaudeLightCore
    public let session: Session        // status already overlaid (.error when applicable)
    public let errorReason: String?    // non-nil only when session.status == .error
}
```

### 4. Icon state (multi-lamp)

Replace the single-lamp `IconState` with per-lamp motions:

```swift
public enum LampMotion: String, Sendable, Equatable { case off, steady, blink, breathe }

public struct IconState: Sendable, Equatable {
    public let red: LampMotion      // off | steady | blink
    public let orange: LampMotion   // off | breathe
    public let green: LampMotion    // off | steady
}

public func iconState(for sessions: [Session]) -> IconState
public func litAlpha(for motion: LampMotion, phase: Double) -> Double
```

- `iconState(for:)` applies the lamp rules above (input sessions already have the
  `.error` overlay applied by the watcher).
- `litAlpha(for:phase:)`: `off → 0`, `steady → 1`, `blink → 0.6 s square wave
  (1.0 / 0.2)`, `breathe → 1.5 s cosine (0.55…1.0)`.
- **Animation clock** runs while any lamp motion is `blink` or `breathe`.

### 5. Renderer

`TrafficLightIcon.image(state: IconState, phase: Double, mono: NSColor) -> NSImage`
draws all three bars: each lamp with motion `!= off` is filled in its state color at
`litAlpha(for: motion, phase:)`; lamps with motion `off` are drawn dim (`mono` at
0.28). Non-template image, fixed size — geometry unchanged from the current fat
traffic light. Red blinking and orange breathing therefore animate independently in
the same image.

### 6. Dropdown

- **No elapsed time.** Rows:
  - `🟠 project — running`
  - `🟢 project — idle`
  - `🔴 project — API error: <reason>`
  - waiting/attention keep today's labels ("waiting for permission" / "awaiting your
    reply").
- **Sort** (`sortedForMenu`): `error (0) → attention (1) → waiting (2) → running (3)
  → idle (4)`, ties by project name.
- **Summary header** breaks errors out. `statusCounts` gains `error`; header parts in
  order `error`, `needYou` (waiting+attention), `working` — e.g. `1 error · 2 working`;
  idle-only → `Idle`; no sessions → header omitted. Pluralize `"1 error"` / `"N errors"`.
- Row dots use the existing non-template `NSImage` dot helper (error/waiting/attention
  → red, running → orange, idle → green).

## Architecture / units

- `ClaudeLightCore` (pure, unit-tested):
  - `apiErrorReason(transcriptJSONL:) -> String?` (new file `APIErrorDetection.swift`).
  - `IconState`/`LampMotion`/`iconState(for:)`/`litAlpha(for:phase:)` (rewrite
    `IconModel.swift`).
  - `SessionStatus.error`; `statusCounts` + `summaryText` + `sortedForMenu` updated
    for `error` (`MenuModel.swift`).
  - `Session.transcriptPath`; `SessionRow` (`Session.swift` / small new file).
- App:
  - Hook shim persists `transcriptPath`.
  - `SessionWatcher`: bounded tail-read + `.error` overlay, publishes `[SessionRow]`,
    `IconState`, summary; animation clock covers blink+breathe.
  - `TrafficLightIcon.image(state:phase:mono:)` multi-lamp.
  - `MenuContent`: rows without time, error label + reason, error-aware header.

## Testing

- **Core (pure):**
  - `iconState` matrix over combinations of {none, idle, running, waiting,
    attention, error} → expected per-lamp motions, covering the model-B pivots:
    `running only → orange breathe`; `waiting+running → red steady, orange OFF`
    (single lamp, as today); `attention+running → red blink, orange off`;
    `error+running → red blink + orange breathe` (two lamps); `error only → red
    blink`; `error+idle → red blink, green off`; `idle only → green`; `none → dim`.
  - `litAlpha` per motion (off/steady/blink boundaries/breathe range).
  - `apiErrorReason`: trailing synthetic error → normalized reason; newer real
    activity after error → nil; no error → nil; multiple errors → latest; reason
    normalization cases; empty/garbage transcript → nil (no crash).
  - `statusCounts`/`summaryText` with errors (pluralization, ordering, idle-only).
  - `sortedForMenu` with `error` first.
- **App (build + manual):** multi-lamp renderer; watcher bounded tail-read + overlay.
  Manual: craft a transcript whose last entry is a synthetic `"API Error:"`, point a
  running session's `transcriptPath` at it → the session flips to red/error in the
  menu within 30 s while a second running session keeps breathing; append a normal
  assistant message → error clears on next refresh.

## Edge cases

- **No `transcriptPath`** (older session, or hook didn't supply it) → skip error
  detection; behaves exactly as today.
- **Transcript unreadable / very large** → bounded tail read (~64 KB); any read or
  parse failure fails safe to "no error".
- **Error then recovery** → `apiErrorReason` returns nil on the next refresh; session
  leaves `.error` automatically.
- **Error on a non-running session** → only `running` sessions are checked; a session
  that already went `idle`/`attention` via a real hook is not overridden.
- **Reason contains user content** → only the synthetic `"API Error:"` prefix is
  parsed and normalized to a short known phrase or a truncated snippet; no arbitrary
  transcript text is surfaced verbatim beyond ~40 chars.

## Out of scope / future

- Detecting silent crashes that leave no transcript trace (killed terminal) — still
  handled only by the 30-minute TTL.
- A dedicated file-watcher on transcripts for sub-30 s error latency.
- Distinguishing error *types* beyond a short reason.
