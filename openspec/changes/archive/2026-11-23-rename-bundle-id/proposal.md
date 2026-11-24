# Proposal

## Why

Clair's bundle identifier, `dev.joshuapark.Clair`, sits under the owner's personal domain. The project now has its own name, `clairbrowser`, and the owner wants the identifier under it: `com.clairbrowser.clair`. Only the owner's own 0.1.x builds exist, so this is the last point where the identifier can change without affecting anyone else. After this change it stays fixed.

## What Changes

- **BREAKING: the bundle identifier becomes `com.clairbrowser.clair`.** The helpers Chromium derives from it follow (`com.clairbrowser.clair.helper`, `.helper.renderer`, `.framework`, `.framework.AlertNotificationService`), and so do Clair's own bundles (`com.clairbrowser.clair.ClairUI`, `.ClairUITests`, `.Probe`, `.RuntimeTests`).
- **Names derived from it follow:** the log subsystem, the sidebar drag type (`com.clairbrowser.clair.sidebar-item`), the bundle that cloud-management policies are read from, and the keychain access group of device-bound session keys.
- **No migration.** macOS treats the new build as a different app: its user defaults (sidebar width, Sparkle state), the default browser choice and the keychain item's access list start fresh. The data folder (`~/Library/Application Support/Clair`) and the keychain item's name ("Clair Safe Storage") don't change, so profiles carry over.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `app-identity`: "Stable bundle identifier" names `com.clairbrowser.clair` and the `com.clairbrowser.clair.` helper prefix.

## Impact

- **Engine:** `patches/clair/branding.patch` (`MAC_BUNDLE_ID`), `patches/clair/data-paths.patch` and the window overlay's log subsystem. The engine key changes, so the engine is rebuilt.
- **`ClairUI`:** the Xcode project's identifiers, the bundle identifier check in `NativeLayer`, the settings and update loggers, the sidebar drag type, and their tests.
- **Packaging and scripts:** `package.sh`, `scripts/verify-app.sh`, `scripts/run-local.sh`, `scripts/clean-code-sign-clones.sh`, and their tests.
- **Tests and tooling:** the runtime suite and the probe identify the app by its bundle identifier.
- **Docs:** `CLAUDE.md`'s fixed identifiers, `docs/building.md`, `docs/updates.md`.
- **`ClairHost.h`, the data folder, the keychain item name and the Sparkle feed:** no change.
