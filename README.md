# Porty

A native macOS menu bar app for tracking local port usage — see what's listening on your machine, which project it belongs to, and kill it or open it in your browser with one click.

## Features

- Live list of listening TCP/UDP ports, refreshed every 2s (deduped across IPv4/IPv6)
- Process name, pid, protocol, and uptime per port
- Git project context — repo name + current branch, resolved from the process's working directory
- Kill a process, open `localhost:<port>` in your browser, or right-click to copy the URL
- Green active-port indicator

## Requirements

- macOS 13+
- Xcode 15+ (or Command Line Tools) with the Swift 6 toolchain

## Build & Run

```bash
# Quick dev run (shows a Dock icon, fine for iterating)
swift run

# Build a proper .app bundle (no Dock icon, menu bar only)
./scripts/build-app.sh release
open .build/Porty.app
```

## Testing

```bash
swift test
```

Unit tests cover port parsing/dedup, uptime parsing/formatting, and git branch/worktree resolution. Requires the Swift Testing framework, which ships with Xcode 16+ (not available under bare Command Line Tools).

## Packaging & Distribution

```bash
# Build a drag-to-Applications DMG (ad-hoc signed)
./scripts/build-dmg.sh
```

For a signed + notarized build (requires a paid Apple Developer account):

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export APPLE_ID="you@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="...."   # or use a stored notarytool profile
./scripts/notarize.sh
```

This signs with hardened runtime, submits to Apple's notary service, and staples the ticket to the DMG. Porty is intentionally unsandboxed (it shells out to `lsof`/`ps`/`kill` to inspect and manage other processes), so no App Sandbox entitlements are requested.

## Status

Feature-complete relative to comparable menu bar port trackers (Ports App, Port Menu): port scanning, project/git context, uptime, kill, open-in-browser, copy URL, dedup. Packaging supports both a quick ad-hoc local build and a real signed/notarized DMG for distribution.
