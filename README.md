# Reservoir

Reservoir is a lightweight native macOS menu-bar monitor for AI usage limits. It currently tracks Codex and Claude, showing current-session usage directly in the menu bar and full current/weekly details in a popover.

The project is intentionally small and local-first: Swift, AppKit, SwiftUI, WebKit, and Foundation only.

## What It Shows

- Menu bar: compact current-session remaining values for both providers, for example `C 95%  A 100%`.
- Popover: provider cards with current session, weekly usage, colored progress bars, reset date/time, last updated, refresh, connect, disconnect, and browser-open actions.
- Stale indicator: `*` after a menu-bar value means Reservoir is showing cached data after a failed refresh.

Provider labels:

- `C`: Codex
- `A`: Claude / Anthropic

## Security Posture

- No Electron.
- No Playwright, Puppeteer, Chromium automation, browser extension, localhost receiver, backend, analytics SDK, telemetry, or crash-reporting SDK.
- No API keys.
- No third-party networking libraries.
- Uses Apple frameworks only: AppKit, SwiftUI, WebKit, Foundation, Security-related platform APIs.
- Stores only normalized local usage snapshots and refresh metadata.
- Does not persist raw page HTML, cookies, auth headers, bearer tokens, query strings, or full network responses.

Local state files:

- `~/Library/Application Support/Reservoir/snapshots.json`
- `~/Library/Application Support/Reservoir/refresh-history.jsonl`

`refresh-history.jsonl` is a capped local ring buffer. Each row contains only provider id, timestamp, status, whether cached data was used, and whether that value is stale.

## Data Collection

Reservoir uses a short-lived `WKWebView` during connect/refresh. It first tries page-visible usage JSON and then falls back to visible text parsing for:

- Codex: `https://chatgpt.com/codex/cloud/settings/analytics`
- Claude: `https://claude.ai/settings/usage`

The WebKit view is released after refresh, and no persistent browser automation process is kept alive.

## Refresh Cadence

- Background refresh: about every 5 minutes with jitter.
- Foreground popover refresh: about every 60 seconds with jitter.
- Manual refresh: available from the popover.
- Disabled or disconnected providers do not refresh.
- On failure, Reservoir keeps the last good cached value and marks it stale only after the cache is older than 30 minutes.

## Build And Run

Requirements:

- macOS 14 or newer
- Xcode Command Line Tools with Swift 6-compatible tooling

Run from source:

```sh
swift run Reservoir
```

Run checks:

```sh
swift run UsageMonitorChecks
```

## Package

Create a local app bundle and ZIP:

```sh
./scripts/package-zip.sh
```

Install on your own Mac:

```sh
./scripts/install-local.sh
```

The installer:

- Stops any running `Reservoir` process.
- Installs only to `~/Applications/Reservoir.app`.
- Removes an old `/Applications/Reservoir.app` copy when possible.
- Clears extended attributes.
- Verifies the ad-hoc signature.
- Registers and opens the installed app.

Reservoir is a menu-bar app. It does not show a Dock icon.

## Share Without Apple Developer ID

You can share the ZIP with trusted users, but macOS will treat it as an unsigned/ad-hoc signed app. This is suitable for trusted personal distribution, not a polished public notarized release.

Recipient install steps:

```sh
mkdir -p "$HOME/Applications"
ditto -x -k Reservoir.zip "$HOME/Applications"
xattr -cr "$HOME/Applications/Reservoir.app"
open "$HOME/Applications/Reservoir.app"
```

If blocked, right-click `Reservoir.app`, choose **Open**, then confirm. They may also need Privacy & Security -> **Open Anyway**.

Important: run only `~/Applications/Reservoir.app`. Avoid launching copies from Downloads, `dist`, or `/Applications`.

## Repository Layout

- `Sources/Reservoir`: macOS app, menu bar, popover, WebKit collector.
- `Sources/UsageMonitorCore`: provider models, parsers, scheduler, local stores, secure logging.
- `Sources/UsageMonitorChecks`: parser, security, storage, and behavior checks.
- `scripts`: build, icon, package, and local install scripts.
- `assets`: app icon sources.
- `mistakes`: project lessons to avoid repeating packaging and collection mistakes.

## License

MIT. See [LICENSE](LICENSE).
