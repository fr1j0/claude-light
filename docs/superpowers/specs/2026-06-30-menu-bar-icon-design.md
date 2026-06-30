# Design — Traffic-light menu-bar status icon + enriched dropdown

Date: 2026-06-30
Status: Approved (pending spec review)

## Goal

Make the menu-bar presence richer and more on-brand without cramming data into the
icon. The **icon stays simple** — the Claude Light traffic light itself, with the
active lamp lit as the status signal. All the detail (per-session list, counts,
activity) lives in the **dropdown**, following the Teams/Slack pattern: a simple
presence indicator up top, everything else one click away.

Rendered design reference (true menu-bar scale + magnified, dark & light): see
`2026-06-30-menu-bar-icon-mockups.png` — the locked style is the **"FAT, squarer bar
lamps"** row.

This supersedes an earlier exploration that put per-state count badges directly in
the menu bar. That was dropped because, at ~18pt, count badges either grew the item
width (shifting neighboring menu-bar icons) or became illegible when stacked. The
dropdown is the right home for "more information."

## Current state

- `ClaudeLightApp.dotImage(for:dim:)` renders a single 13pt colored dot
  (red/orange/green) as a non-template `NSImage`. Red dims on/off every 0.6s when a
  session needs attention (`SessionWatcher.attentionPhase`).
- `Aggregate.aggregateLight(for:)` collapses sessions to one color: red if any
  `.waiting`/`.attention`, else orange if any `.running`, else green (also green when
  there are **no** sessions).
- `MenuContent` lists each live session as `project — <friendly status>` with a
  colored `circle.fill`, then Install/Remove-hooks and Quit.

## Design

### 1. Menu-bar icon — fat traffic light, active lamp lit

A distinctive **fat-style** traffic-light glyph: a chunky rounded-rectangle **outline
housing** with three stacked **rectangular bar lamps** (squared-off, small corner
radius — not round dots). Exactly one bar is lit in its state color; the other two are
dimmed. The housing outline and dimmed bars use an **appearance-adaptive** color
(white on a dark menu bar, black on a light one).

Geometry (relative, final values tuned in implementation): housing aspect ~13:17
(w:h) so it reads "fat" rather than a thin pill; each bar lamp ~60% of housing width,
~26% of inner height, corner radius ~0.22× the bar height; three bars evenly stacked
top→bottom = red→orange→green.

Aggregate lamp selection (priority order):

| Condition (first match wins)              | Lamp lit        |
|-------------------------------------------|-----------------|
| No live sessions                          | none (all dim)  |
| Any session `.waiting` or `.attention`    | top — red       |
| Else any session `.running`               | middle — orange |
| Else (sessions exist, all `.idle`)        | bottom — green  |

State is encoded by **both lamp position and color**, which is more distinguishable
than a single dot and friendlier to colorblind users.

**Width is fixed** (the glyph never changes size), so neighboring menu-bar items
never shift.

### 2. Motion

Driven by an animation clock (see Architecture). Applies to the **lit lamp** only:

- **Blink** (~0.6s on/off, lit alpha → ~0.2 and back): when the lit lamp is **red and
  a session needs your reply** (any `.attention`). A permission-only red
  (`.waiting`, no `.attention`) stays **steady** — preserving the existing
  attention/permission distinction.
- **Breathe** (~1.5s soft pulse, lit alpha oscillates ~0.55–1.0): when the lit lamp is
  **orange** (working). Conveys "work is happening" without being alarming.
- **Steady**: green (idle) and the all-dim no-sessions state.

### 3. Dropdown — enriched session list (native `.menu` style)

Retains `MenuBarExtraStyle(.menu)` (matches the native Teams status menu look:
colored `circle.fill` + text). Structure:

```
●  1 needs you · 2 working          ← summary header (secondary text)
────────────────────────────
🔴 myapp — awaiting your reply · 12s
🟠 api   — running · 2m
🟠 web   — running · 5m
🟢 docs  — idle · 8m
────────────────────────────
Install / Remove Claude Code hooks
Quit Claude Light
```

- **Summary header**: a secondary (disabled) row — a colored dot in the aggregate lamp
  color plus a words-and-counts summary built from the session mix.
- **Session list**: a single **flat list sorted by urgency** — `.attention`, then
  `.waiting`, then `.running`, then `.idle`; ties broken by project name (stable, so
  rows don't reorder as timestamps tick). Each row: colored `circle.fill` +
  `project — <friendly status> · <relative time>`.
- **Relative time** from each session's `updatedAt` (e.g. `12s`, `2m`, `3h`, `2d`).
- **Empty state**: "No active Claude Code sessions" (no header), then the actions.
- **Actions** unchanged: Install/Remove Claude Code hooks, Quit Claude Light.
- Session rows are **non-interactive** for now (focusing a specific terminal is out of
  scope — see Future).

#### Summary header text

Built from counts `needYou = waiting + attention`, `working = running`, `idle`:

- Parts, in order, joined by " · ":
  - `needYou > 0` → `"<n> need(s) you"` ("1 needs you" / "2 need you")
  - `working > 0` → `"<n> working"`
  - if no active parts and `idle > 0` → `"Idle"`
- No live sessions → header omitted (empty-state text covers it).

## Architecture

Keep all decision logic as **pure, unit-tested functions in `ClaudeLightCore`**; keep
AppKit drawing thin and dumb.

### `ClaudeLightCore` (new, pure, no AppKit)

```swift
public enum IconLamp: Sendable { case red, orange, green, off }

public struct IconState: Sendable, Equatable {
    public let lamp: IconLamp
    public let blink: Bool      // red + needs reply
    public let breathe: Bool    // orange / working
}
public func iconState(for sessions: [Session]) -> IconState

public struct StatusCounts: Sendable, Equatable {
    public let needYou: Int     // waiting + attention
    public let working: Int     // running
    public let idle: Int
}
public func statusCounts(for sessions: [Session]) -> StatusCounts
public func summaryText(for counts: StatusCounts) -> String?   // nil when no sessions

public func sortedForMenu(_ sessions: [Session]) -> [Session]  // urgency, then project
public func relativeTime(secondsAgo: TimeInterval) -> String   // "12s" / "2m" / "3h" / "2d"
```

`aggregateLight` may be retained for internal reuse, but the icon is driven by
`iconState` (it distinguishes the no-sessions `.off` case, which `aggregateLight`
does not).

### App layer (thin)

- **Glyph renderer**: `trafficLightImage(lamp: IconLamp, litAlpha: CGFloat, mono: NSColor) -> NSImage`
  — draws the fat outline housing + three rectangular bar lamps (housing outline and
  dim bars in `mono`, the lit bar in its state color at `litAlpha`). Fixed canvas size;
  non-template image. No business logic.
- **Appearance adaptation**: derive `mono` (white/black) from the menu bar's effective
  appearance and re-render on change. Recommended mechanism: read
  `NSApp.effectiveAppearance` and observe appearance changes (KVO on
  `effectiveAppearance` / the interface-theme-changed notification). Final mechanism to
  be settled in the implementation plan; not a design blocker.
- **`SessionWatcher`**: in `reload()`, also derive and publish `iconState`,
  `statusCounts`/`summaryText`, and the `sortedForMenu` sessions. Replace the single
  `attentionPhase` Bool with an **animation clock**: one repeating timer (~0.08s) that
  runs **only while `blink || breathe`**, accumulating an elapsed-seconds `phase`
  (`@Published`). When idle / no animated lamp, the timer is invalidated (no wasted
  redraws). The label view computes `litAlpha` from `iconState` + `phase`:
  - blink → square wave at 0.6s (alpha 1.0 vs ~0.2)
  - breathe → `0.55 + 0.45 * (0.5 + 0.5*cos(2π * phase / 1.5))`
- **`MenuBarExtra` label**: `Image(nsImage: trafficLightImage(lamp:litAlpha:mono:))`,
  recomputed when `iconState`/`phase`/appearance change.
- **`MenuContent`**: render the summary header (secondary text), the
  `sortedForMenu` rows with `project — status · relativeTime`, the empty state, and the
  existing actions.

## Edge cases

- **No live sessions** → lamp `.off` (all dim), no header, "No active Claude Code
  sessions" + actions.
- **Permission-only red** (`.waiting`, no `.attention`) → red lit, **steady** (no
  blink).
- **Mixed waiting + attention** → red lit, blinking (attention present), header counts
  both under `needYou`.
- **Stable ordering**: secondary sort by project name avoids row reordering as relative
  times tick.
- **Light vs dark menu bar**: housing/dim lamps adapt; lit lamp colors are bright
  enough to read on both.

## Testing

- **Core (pure, exhaustive):**
  - `iconState` across all session mixes (empty, idle-only, working, waiting,
    attention, and combinations) → expected lamp + blink/breathe flags.
  - `statusCounts` and `summaryText` (pluralization, ordering, idle-only "Idle", nil
    when empty).
  - `sortedForMenu` ordering (urgency priority + project tiebreak).
  - `relativeTime` boundaries (seconds/minutes/hours/days).
- **App:** keep the renderer logic-free; a smoke check that `trafficLightImage`
  returns a non-nil image of the expected fixed size is sufficient.

## Out of scope / future

- Clicking a session row to focus/raise its terminal (no reliable handle today).
- User-configurable colors or motion.
- Per-state count badges in the menu bar (explicitly rejected — illegible/shifty at
  size).
