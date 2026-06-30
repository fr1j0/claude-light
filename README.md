# Claude Light

A native macOS menu-bar app that shows the status of your Claude Code sessions at a glance.

## What It Does

Claude Light monitors all your Claude Code sessions and displays a traffic-light status in the menu bar:

- **🔴 Red** — an agent needs your input (permission prompt / waiting on you)
- **🟠 Orange** — an agent is running
- **🟢 Green** — idle or finished, ready for the next task

When you have multiple sessions running, the menu-bar icon shows the aggregate status (red wins), and the dropdown lists each session individually with its current state and project name.

## How It Works

Claude Light integrates with Claude Code through a simple hook shim that writes session state to `~/.claude-light/sessions/`. The app watches this folder and updates its display whenever a session changes.

**Installation flow:**
1. Install Claude Light from Homebrew or GitHub Releases.
2. Launch the app — a menu-bar icon appears.
3. Click "Install Claude Code hooks" to wire the hook shim into `~/.claude/settings.json`.
4. Your next Claude Code prompt will light up the menu.

For the full technical design, see [docs/superpowers/specs/2026-06-30-claude-light-design.md](docs/superpowers/specs/2026-06-30-claude-light-design.md).

## Installation

### Via Homebrew (Recommended)

```bash
brew tap fr1j0/claude-light
brew install --cask claude-light
```

### From GitHub Releases

Download the latest notarized `.app` from [GitHub Releases](https://github.com/fr1j0/claude-light/releases). Verify the SHA-256 checksum against the published value to confirm authenticity.

## First Run

1. Launch Claude Light.
2. Click the menu-bar icon.
3. Select **"Install Claude Code hooks"** — this safely merges hook entries into your `~/.claude/settings.json`.
4. Click "Remove hooks" at any time to cleanly uninstall.

## Security & Trust

Claude Light is open source and auditable — because it edits your settings and runs on every Claude Code hook, you can read the source and verify it's safe.

**Install only from official Releases** at https://github.com/fr1j0/claude-light/releases. The official build is signed and notarized by the maintainer's Apple Developer ID, removing both the "unidentified developer" warning and the risk of tampering.

Always verify the published SHA-256 checksum before running the app.

## License & Trademark

Licensed under [Apache-2.0](LICENSE). The name "Claude Light", logo, and icon are **not** licensed under Apache-2.0 — see [TRADEMARK.md](TRADEMARK.md) for details.

"Claude" is a trademark of Anthropic. This is an independent community project, not affiliated with or endorsed by Anthropic.
