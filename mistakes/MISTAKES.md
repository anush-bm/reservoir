# Reservoir Mistakes Log

Keep this short and blunt. Check it before changing packaging, collection, or distribution.

## Browser Extension Detour

- Mistake: implemented a Chrome/Edge companion extension after only discussing it as an option.
- Rule: do not add browser extensions, companion agents, localhost receivers, or new install surfaces without explicit approval.
- Current decision: Reservoir is native-only WebKit unless the user explicitly reopens that discussion.

## Duplicate App Copies

- Mistake: launched copies from `dist/`, `/Applications`, and `~/Applications`; all wrote the same cache and made refresh times look stale.
- Rule: install to `~/Applications/Reservoir.app` for local unsigned use.
- Rule: installer must stop running `Reservoir` processes and remove old `/Applications/Reservoir.app` copies.
- Rule: keep the single-instance lock in the app.
- Rule: tell users to run only `~/Applications/Reservoir.app`; never run `dist/Reservoir.app` as a daily app.

## Packaging Without Developer ID

- Mistake: assumed a plain zip would be enough.
- Rule: personal packaging must ad-hoc sign the final `.app`, clear xattrs, zip with `ditto`, then validate extracted output.
- Rule: public smooth distribution still needs Developer ID signing and notarization.

## Refresh Semantics

- Mistake: initial app could show stale cache after relaunch.
- Rule: if cached data is older than 10 minutes or marked stale, refresh once on startup.
- Rule: avoid eager dashboard loads on first launch when no cache exists.
