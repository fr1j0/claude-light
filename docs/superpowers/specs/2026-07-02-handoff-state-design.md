# Handoff Session State — Design

**Date:** 2026-07-02
**Branch:** `feat/handoff-state`
**Motivation:** A session that ends its turn with "Please review the spec and if it looks
right I'll move on" shows green (idle) today, even though no progress happens until the
user acts. PR #33 deliberately narrowed `attention` to concise questions to kill false
positives; this left a false-negative class — *approval asks* — that the user's
spec-first workflow hits constantly. `handoff` names that class: turn ended, prose infers
Claude handed the user a work item (review, approval, sign-off).

## Semantics

Two kinds of "blocked on the user":

| | `waiting` / `attention` | `handoff` (new) |
|---|---|---|
| Source | Harness-confirmed (Notification hook / concise question on Stop) | Prose-inferred on Stop |
| Session | Held mid-turn or asked directly | Turn complete, parked |
| Confidence | High | Lower (heuristic) |

The confidence difference is expressed in the **label**, not the color: at the icon
level both mean "come back".

## 1. State model (`Session.swift`)

Add `case handoff` to `SessionStatus` (raw value `"handoff"`, Codable like the rest).
No other `Session` changes. Hook binary and app ship together in one version bump;
unknown-status decode behavior is unchanged.

## 2. Detection (new `HandoffDetection.swift`, wired in `HookAction.swift`)

On `Stop`, evaluated **only when the existing attention check fails**.
`textEndsWithQuestion` and its PR #33 tuning stay byte-for-byte untouched.

Algorithm (`textEndsWithHandoffAsk`):

1. Strip fenced/inline code (reuse `strippingCode`).
2. Take the **last prose paragraph**: the last non-empty block after splitting the
   stripped text on blank lines.
3. If that paragraph is ≤ 240 chars (reuse `questionMaxLength` — "concise ask" stays
   one tunable concept) AND (it ends with `?` OR contains an approval-ask phrase,
   case-insensitive) → handoff. Otherwise → idle.

Initial phrase list (tunable constant, same spirit as `questionMaxLength`):

```
please review, let me know, sign off, sign-off, approve,
should i proceed, if it looks right, if it looks good, waiting for your
```

`Stop` branch precedence in `action(for:)`:
concise question → `.attention` (unchanged) → else handoff ask → `.handoff` → else `.idle`.
Unparsable/missing transcript → `.idle`, exactly like today (fail-safe).

## 3. Icon (`IconModel.swift`)

`handoff` joins `waiting` in the steady-red branch:

```
red blink      = attention / error   (hard block, confirmed)
red steady     = waiting OR handoff  (come back)
orange breathe = running
green steady   = idle
```

- Steady red; suppresses orange (as waiting does); suppresses green.
- `aggregateLight`: handoff → `.red`.
- `aggregateNeedsAttention` (drives blink) stays attention-only — handoff never blinks.
- No new lamp motion; `isAnimating` unchanged.

Decision note: a distinct visual (steady orange / breathing green) was considered and
rejected — the icon answers "do I need to go back?", and handoff answers yes. The
confirmed-vs-inferred distinction lives in the dropdown label.

## 4. Dropdown (`MenuModel.swift`, `MenuContent.swift`)

- Row: **red dot**, label **"review requested"**.
- `statusCounts`: handoff folds into `needYou` (icon and row are red; "2 need you"
  counting it is consistent — no new summary segment).
- Sort rank: `error(0) > attention(1) > waiting(2) > handoff(3) > running(4) > idle(5)`.
  Below waiting because a permission prompt stalls an in-flight turn — seconds matter
  more there than at a parked handoff.

## 5. Testing (TDD, mirroring PR #33)

- `HandoffDetectionTests`:
  - phrase hit — the motivating closing paragraph ("Please review — especially the
    three flagged decisions — and if it looks right I'll move on to the implementation
    plan.") as a fixture → true
  - long turn whose trailing paragraph ends with `?` → true
  - `?` only inside code (fenced and inline) → false
  - trailing paragraph > 240 chars → false
  - plain completion ("All 131 tests pass.") → false
  - case-insensitive phrase match → true
- `HookActionTests`: Stop + concise question → attention (unchanged); Stop + approval
  prose → handoff; Stop + plain prose → idle; attention wins over handoff.
- `AggregateTests`: handoff → red; needsAttention stays false.
- `IconModelTests`: handoff → red steady; suppresses orange and green; not animating.
- `MenuModelTests`: counts fold into needYou; sort rank; (label mapping lives in the
  app layer, covered by the enum switch being exhaustive).
- `SessionTests`: codable round-trip for `"handoff"`.

## Out of scope

- Verifying whether Claude Code's 60s idle `Notification` ("Claude is waiting for your
  input") reaches the hook — a semantic, non-heuristic signal that could complement or
  partially subsume this heuristic. Worth a separate investigation.
- Any change to the attention heuristic or TTL.
