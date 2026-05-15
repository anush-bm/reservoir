# Reservoir Personal Release

This release path is for personal or trusted-user distribution without an Apple Developer account.

## Build the ZIP

```sh
cd /Users/anushbm/davenport/ai/AIUsageMonitor
./scripts/package-zip.sh
```

Output to share:

```text
dist/Reservoir.zip
```

## Install on your own Mac

Recommended:

```sh
./scripts/install-local.sh
```

Manual:

```sh
mkdir -p "$HOME/Applications"
ditto -x -k dist/Reservoir.zip "$HOME/Applications"
xattr -cr "$HOME/Applications/Reservoir.app"
open "$HOME/Applications/Reservoir.app"
```

Reservoir is a menu-bar app. It does not show a Dock icon. Look for its compact C/A usage text in the macOS menu bar.

## Share without Apple Developer ID

Send only:

```text
dist/Reservoir.zip
```

Recipient commands:

```sh
mkdir -p "$HOME/Applications"
ditto -x -k Reservoir.zip "$HOME/Applications"
xattr -cr "$HOME/Applications/Reservoir.app"
open "$HOME/Applications/Reservoir.app"
```

If blocked, right-click `Reservoir.app` and choose **Open**. They may also need Privacy & Security -> **Open Anyway**.

Do not run copies from multiple locations. Use only:

```text
~/Applications/Reservoir.app
```

If macOS blocks it:

1. Right-click `~/Applications/Reservoir.app`.
2. Choose **Open**.
3. Confirm **Open** again.

If it is still blocked because the file is quarantined, and you built this ZIP yourself:

```sh
xattr -dr com.apple.quarantine "$HOME/Applications/Reservoir.app"
open "$HOME/Applications/Reservoir.app"
```

## Important limitation

Without an Apple Developer account, Reservoir cannot be Developer ID signed or notarized. People outside your trusted circle will see macOS Gatekeeper warnings.
