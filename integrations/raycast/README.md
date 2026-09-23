# Portly for Raycast

Raycast commands backed by the [Portly](https://hellohopper.github.io/portly/) CLI and its `portly://` links.

- **Listening Ports** — search every listening port by number, process, framework or project; open it in the browser, copy its URL, restart it (⌘R), kill it (⌃X, with confirmation), force-kill it (⌃⇧X), pin it or show it in Portly.
- **Copy Free Port** — copies an unused port from the common dev ranges.

Requires Portly (`brew install --cask hellohopper/portly/portly`); the extension finds its CLI in `/opt/homebrew/bin`, `/usr/local/bin` or inside `/Applications/Portly.app`.

## Develop

```bash
npm install
npm run dev        # opens the extension in Raycast
npm run typecheck
```
