# Design

## Context

`app-identity` fixed the bundle identifier as `dev.joshuapark.Clair` with the first shipped build. Those builds (0.1.0 to 0.1.2) only ever reached the owner, so changing it now costs nothing beyond the owner's own install.

## Goals / Non-Goals

**Goals:**
- The behavior in `specs/`: every bundle and every name derived from the identifier uses `com.clairbrowser.clair`.

**Non-Goals:**
- Migrating an installed Clair's user defaults, default browser choice or keychain access to the new identifier.
- Changing the data folder, the keychain item's name, the Sparkle feed or the version scheme.

## Decisions

### D1. All lowercase, suffixes kept

The main identifier is `com.clairbrowser.clair`, lowercase like the domain it comes from. Chromium derives its helpers' identifiers from `MAC_BUNDLE_ID` by appending fixed suffixes, so they follow by themselves. Clair's own bundles keep their suffixes (`.ClairUI`, `.ClairUITests`, `.Probe`, `.RuntimeTests`), so only the prefix changes.

### D2. Everything derived from the identifier follows it

The log subsystem, the sidebar drag type and the two places `data-paths.patch` names the bundle (the cloud-management policy domain and the device-bound session keys' access group) all move to the new identifier, so nothing is left under the old domain.

### D3. No migration

Clair isn't released, so there is nothing to migrate for anyone but the owner. An old install keeps its identifier; installing the new build gives a fresh set of user defaults and asks again for the keychain item and the default browser.

## Risks / Trade-offs

- **[Sparkle may refuse to update an old install to the new identifier]** → the owner installs the new build from its DMG once. No one else has an old build.
- **[macOS asks for keychain access again]** → the keychain item's access list names the old app's code signature. Allowing access once fixes it.
