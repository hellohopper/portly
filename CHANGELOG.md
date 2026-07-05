# Changelog

All notable changes to Portly are documented here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## [0.5.2] - 2026-07-04

### Fixed
- Overlapping port scans (2s timer + kill/restart/ignore actions each triggering their own) could apply out of completion order, letting an older, slower scan silently overwrite fresher results and flash the list backward
- A port's row identity changed when its TCP and UDP listeners merged into "TCP+UDP", causing SwiftUI to treat the merge as a new row instead of updating in place (breaking row animation and in-progress keyboard focus)

## [0.5.1] - 2026-07-04

### Fixed
- `portly version` printed "dev" instead of the real version when run via the Homebrew-installed `portly` symlink (the normal way anyone would invoke it) — `Bundle.main` was resolving off the symlink path rather than the actual binary location

## [0.5.0] - 2026-07-03

### Added
- `portly` CLI companion, shipped inside the app bundle — `portly list` (table or `--json`), `portly kill <port>`. Homebrew installs the command automatically; manual installs can symlink `Portly.app/Contents/MacOS/portly-cli`
- HTTP health badge — TCP ports are HEAD-probed and show their status code (green 2xx/3xx, orange 4xx, red 5xx)
- Process tree context — rows show their wrapper chain (e.g. `npm → node`) as a tooltip, with a "Kill process tree" context-menu action that never touches shells or terminals
- `.portly.json` project config — check in `{ "labels": { "3000": "web frontend" } }` at a repo's root to auto-label ports for the whole team (manual labels still win)
- Port history — rolling log of open/close events with timestamps, persisted across launches, behind a clock icon in the footer
- Keyboard navigation — ↑/↓ move a highlighted row (works while searching), Enter opens in browser, ⌘⌫ kills, Esc clears the search
- "Copy as curl" context-menu action

### Changed
- Shared scanning/enrichment logic split into a PortlyCore library backing both the app and the CLI

### Fixed
- Daemons running from `/` no longer show a bogus "/" project badge

## [0.4.1] - 2026-07-03

### Fixed
- "Download & Install" now stages the new app bundle in a writable temp directory before swapping it in — replacing directly from the read-only DMG mount failed at the final step
- Network throughput samples are no longer dropped for processes whose names contain commas
- Bulk kill now kills every selected port, including selected rows hidden by an active search filter
- Search matches custom per-port labels
- Ignoring a pinned process no longer fires a false "pinned port stopped" notification

## [0.4.0] - 2026-07-02

### Added
- Live network throughput (↓/↑ bytes per second) per port, shown alongside CPU/MEM. Backed by a single long-running `nettop -d` process rather than re-launching it every poll, since `nettop` takes several seconds to start up.

## [0.3.1] - 2026-07-01

### Added
- One-click "Download & Install" in the update banner — downloads the latest release's DMG, swaps the running app bundle in place, and relaunches automatically. Falls back to opening the release page when the app isn't running from `/Applications` (e.g. a dev build) or no DMG asset is published.

## [0.3.0] - 2026-07-01

### Added
- Launch at Login toggle (via `SMAppService`)
- Menu bar icon tints red when a pinned port dies, and clears once you open the menu
- Ignore list — right-click a port to hide it (and its process) from the list going forward, manage the list from Settings
- Export the current port list as JSON or CSV
- Quick restart — kill a process and relaunch its exact command line in the same working directory
- Custom global hotkey — rebind the toggle shortcut (default ⌘⇧P) from Settings
- Per-port custom labels (e.g. "staging API") that persist across launches
- New Settings popover (gear icon in the footer) consolidating the above

## [0.2.0] - 2026-07-01

### Added
- Search/filter box in the dropdown — matches port, process name, framework label, project name, and git branch
- Pin favorites to the top of the list; remaining ports grouped alphabetically by project (with an "Other" bucket)
- Notifications when a new port starts listening, or when a pinned port stops unexpectedly
- Docker awareness — flags ports forwarded through Docker Desktop's host process with a badge, and makes them searchable via "docker"
- Bulk selection: select multiple rows and kill them in one action
- In-app update check against GitHub Releases, with a banner linking to the new version when available

## [0.1.0] - 2026-07-01

Initial release.

### Added
- Live list of listening TCP/UDP ports, refreshed every 2s, deduped across IPv4/IPv6 and merged into one row when a process listens on both protocols for the same port
- Git project context — repo name and current branch, resolved from the process's working directory (including worktree checkouts)
- Uptime, CPU%, and memory% per process, plus a color-coded energy indicator
- Framework-aware labeling (Vite, Next.js, Rails, Django, Flask, FastAPI, Node, Bun, Deno, and more)
- Kill a process, reveal its owning Terminal.app tab, open `localhost:<port>` in the browser, or copy the URL
- Global hotkey (Cmd+Shift+P) to toggle the menu
- System/Light/Dark theme toggle
- DMG installer, SHA-256 checksum publishing, and a Homebrew tap (`hellohopper/portly`)
- MIT license, showcase website ([hellohopper.github.io/portly](https://hellohopper.github.io/portly/))

[0.5.2]: https://github.com/hellohopper/portly/releases/tag/v0.5.2
[0.5.1]: https://github.com/hellohopper/portly/releases/tag/v0.5.1
[0.5.0]: https://github.com/hellohopper/portly/releases/tag/v0.5.0
[0.4.1]: https://github.com/hellohopper/portly/releases/tag/v0.4.1
[0.4.0]: https://github.com/hellohopper/portly/releases/tag/v0.4.0
[0.3.1]: https://github.com/hellohopper/portly/releases/tag/v0.3.1
[0.3.0]: https://github.com/hellohopper/portly/releases/tag/v0.3.0
[0.2.0]: https://github.com/hellohopper/portly/releases/tag/v0.2.0
[0.1.0]: https://github.com/hellohopper/portly/releases/tag/v0.1.0
