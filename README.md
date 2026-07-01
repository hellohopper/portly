# Porty

A native macOS menu bar app for tracking local port usage — see what's listening on your machine, which process owns it, and kill it with one click.

## Requirements

- macOS 13+
- Swift toolchain (Xcode or Command Line Tools)

## Build & Run

```bash
# Quick dev run (shows a Dock icon, fine for iterating)
swift run

# Build a proper .app bundle (no Dock icon, menu bar only)
./scripts/build-app.sh release
open .build/Porty.app
```

## Status

Phase 1: basic port scanning via `lsof`, menu bar list, kill action.
