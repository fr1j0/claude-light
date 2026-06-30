# Claude Status Light — Design

**Date:** 2026-06-30
**Status:** Approved design, pre-implementation
**Type:** Free / open-source macOS menu-bar utility (no commercial intent)

## Problem

When a Claude Code session is working, you switch to another window or your phone,
then keep switching back just to check whether it's still running, waiting for you,
or already done. That context-switching tax is the problem.

A working DIY single-session version already exists (Claude Code hooks driving a light).
This spec covers turning it into a polished, shareable, multi-session menu-bar app.

## Goal

A native macOS **menu-bar app** that shows an always-visible traffic-light status for
all running Claude Code sessions:

- 🔴 **Red** — an agent needs your input (permission prompt / blocked on you)
- 🟠 **Orange** — an agent is running
- 🟢 **Green** — idle / finished, ready for the next task

The user often runs **several sessions at once**, so the menu-bar icon shows one
aggregate light and the dropdown lists each session individually.

## Non-goals (v1, YAGNI)

- Click-to-focus the originating terminal
- History / analytics / time tracking
- Sounds or banner notifications
- Remote / cross-machine / cloud-agent sessions
- Non-macOS support
- Per-session custom colors

All are easy to add later if anyone asks; none are needed to be useful.

## Architecture

Five small, independently-testable units:

### 1. Hook shim
One tiny script (`claude-statuslight-hook`) that every Claude Code hook invokes.
It reads the hook JSON from stdin (for `session_id` and `cwd`), takes a status
argument, and writes/updates/deletes exactly one session file. Single responsibility.

For the `Notification` hook it also inspects the payload's `message` to discriminate
permission requests (→ red) from the idle "waiting for your input" nudge (→ ignore).

### 2. Status store
A folder, `~/.claude-statuslight/sessions/`, holding one JSON file per session:

```json
{
  "session_id": "abc123",
  "status": "running",          // running | waiting | idle
  "project": "vatios",          // basename of cwd, for the dropdown label
  "cwd": "/Users/.../vatios",
  "updated_at": "2026-06-30T11:20:00Z"
}
```

The interface between "the world" and the app is just these files. Anything can write
them, which keeps the app decoupled and trivially extensible to other sources later.

### 3. Watcher + model (in-app)
FSEvents watches the folder, parses files into an in-memory session list, drops/grays
sessions whose `updated_at` is stale (crash safety — a force-killed terminal may never
fire `SessionEnd`), and computes the aggregate color.

- **Staleness TTL:** a session with no activity for ~30 min is treated as dead and dropped.

### 4. Menu-bar UI
SwiftUI `MenuBarExtra`. The menu-bar icon is the aggregate light. The dropdown lists
each session by project name, its individual color, and how long it's been in that state.

- **Aggregate rule:** any red → red; else any orange → orange; else green.
  Red wins because it's the only state actively costing the user time.

### 5. Hook installer (productization keystone)
A built-in first-run action that idempotently merges the hook entries into
`~/.claude/settings.json` (never clobbering existing hooks) and places the shim script.
A "Remove hooks" action cleanly reverses it. Nothing is modified without explicit consent.

### Data flow

```
Claude Code fires hook
  → shim writes/updates/deletes session file
    → FSEvents wakes the app
      → model recomputes aggregate + per-session state
        → menu-bar icon + dropdown re-render
```

## State machine (hook → state mapping)

| Hook              | Meaning                                   | → State            |
|-------------------|-------------------------------------------|--------------------|
| `SessionStart`    | session opened / resumed                  | 🟢 green (idle)    |
| `UserPromptSubmit`| user sent a prompt                        | 🟠 orange (running)|
| `PreToolUse`      | a tool runs (incl. after permission grant)| 🟠 orange (running)|
| `Notification`*   | permission needed / waiting on user       | 🔴 red (waiting)   |
| `Stop`            | Claude finished responding                | 🟢 green (idle)    |
| `SessionEnd`      | session closed                            | delete file        |

\* **Critical correctness detail:** the `Notification` hook fires for *both* permission
requests *and* the idle "Claude is waiting for your input" nudge (~60s after going quiet).
Mapping both to red would flip a finished green session to red on its own — the single
worst failure mode for a tool whose value is "red means look at me." The shim must inspect
the `message` field and go red **only** on permission-type notifications; the idle nudge is
ignored (session stays green).

**Red → orange recovery:** there is no explicit "permission granted" hook, but `PreToolUse`
fires the moment Claude resumes after approval, naturally flipping red back to orange.

**Green is intentionally overloaded:** "just opened, awaiting first prompt" and "task
finished" are both green/idle, matching the original definition. No need to distinguish.

## Distribution & trust

Open source is the *trust mechanism*, not a liability: because the app edits
`~/.claude/settings.json` and runs a script on every hook, users must be able to read the
shim and confirm it's harmless. Closing the source would destroy that and still wouldn't
prevent repackaging. So: stay OSS, and instead make the official build verifiable and
protect the name.

- **License:** Apache-2.0 (explicit trademark clause) + a `TRADEMARK.md`: fork the code
  freely, but forks may not use the name/icon or call themselves official → blocks
  malware impersonation.
- **Provenance:** GitHub Actions builds the official binary with build attestation and
  published SHA-256 checksums. README: "install only from official Releases."
- **Notarization:** the official build is signed with the maintainer's Apple Developer ID
  and notarized. A malware fork cannot reuse the signature, and notarization also removes
  the "unidentified developer" Gatekeeper friction. (Developer account already owned, so
  no extra cost.)

**You cannot technically prevent forks of public source** — licenses govern legal use, not
copying. The achievable goal is: the real build is cryptographically yours and verifiable,
and fakes are legally barred from wearing your name.

## Install flow (make-or-break UX)

1. `brew tap <owner>/claude-statuslight && brew install --cask claude-statuslight`
   (or download the notarized `.app` from Releases).
2. Launch → menu-bar icon appears. First-run panel: **"Install Claude Code hooks?"**
   → click merges hook entries into `~/.claude/settings.json` and drops the shim.
   A "Remove hooks" button reverses it.
3. Next prompt sent to any Claude Code session lights it up.

## Testing strategy

Scaled to a fun OSS project — light but real, weighted toward the one true bug risk.

- **Shim (most coverage):** stdin-JSON + status arg → correct file write/update/delete,
  including `Notification` message discrimination (permission → red vs idle → ignored).
- **Model:** aggregate rule (red-wins) and staleness/TTL dropping over fixture files.
- **Installer:** idempotent merge into a sample `settings.json` (existing hooks preserved)
  and clean removal.
- **UI:** manual/smoke only — not worth automating for v1.

## Tech stack

- **App:** Swift / SwiftUI, `MenuBarExtra`.
- **Shim:** POSIX `sh` (or a compiled Swift helper bundled in the `.app`), readable for audit.
- **CI/dist:** GitHub Actions (build + notarize + attest + checksums), Homebrew cask tap.
