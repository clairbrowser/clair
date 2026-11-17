# Proposal

## Why

`arc-extension-experience` restored the Chrome Web Store, so people install extensions from it. When Google finds that a store extension is malware, or takes it down for a policy violation or as potentially unwanted, Chrome turns it off within hours. Clair doesn't, because each of the ways Chrome learns about it is missing:

- **Update check flags.** Google's update service marks a pulled extension in its answer to an update check: `_malware`, `_policy_violation` or `_potentially_uws`. Only the JSON protocol that Chromium's `UpdateService` speaks carries these. Clair checks store extensions through the older XML protocol (`ExtensionDownloader`), whose answers carry versions and download addresses only. ungoogled-chromium also removed the code that acts on the flags, and left `ExtensionRegistrar`'s blocklist and greylist handlers empty.
- **Safe Browsing.** Its extension blocklist is compiled out.
- **The store's metadata service** (`CWSInfoService`). It runs only with Google Chrome's official API key, which Clair can't ship.

A hand-made JSON update check confirmed that the update service answers a request stripped to what Clair's XML checks already send. For an extension Google pulled as malware, it answered `"_malware":"true"`, both as `chromecrx` and as Chromium's own `chromiumcrx`. The update check is the one source Clair can use. Clair also has no recorded decision on any of this: the `extensions` spec says what's restored, not what happens to a pulled extension.

## What Changes

- **Store extensions update through Chromium's `UpdateService`** and Google's JSON update service, instead of `ExtensionDownloader`. Extensions with their own update server, and installs that aren't finished yet, keep using `ExtensionDownloader`. An extension with no update URL is still never checked.
- **Store update checks send no more than they do today.** Each check carries:
  - each extension's ID, version and install source;
  - Clair's Chromium version, channel and language;
  - the platform (`mac`, `arm64`);
  - the protocol's random per-request IDs.

  It doesn't carry the macOS version, hardware details, install dates, install IDs, cohorts, enabled state or activity pings. No event pings are sent after an install or update.
- **A flagged extension is turned off, as Chrome does:**
  - **Malware:** the extension is unloaded and can't be turned back on, only removed. A Clair dialog on the frontmost window names it, using Chromium's own wording.
  - **Policy violation or potentially unwanted:** the extension is turned off. `chrome://extensions` gives the reason, and the user can turn it back on.

  If the store clears the flag, the extension comes back as Chrome would bring it back.
- **A rule for which Google services Clair turns back on.** Every exception so far restores a Google feed that protects users, which ungoogled-chromium removes along with everything else Google. `chromium-engine` now says so:
  - Clair turns a service back on only if it's the store's or protects users from harm;
  - it does so only through a change that adds the service to a list and says what each request sends;
  - each service sends no more than it needs.

  Convenience services, such as sync, translation or downloaded media components, need a change to the rule first.
- **The rest of ungoogled-chromium's Google-service removals stay:** Safe Browsing, the store metadata service, Enhanced Safe Browsing's allowlist, and the component updater.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `extensions`: "Extensions update automatically" says which server store extensions are checked with and what a check sends. A new requirement covers what happens to an installed extension the store has flagged, including the notice.
- `chromium-engine`:
  - A new requirement, "Google services Clair turns back on", sets the rule for undoing ungoogled-chromium's Google removals:
    - only the Chrome Web Store, or a feed that protects users from harm;
    - each one added by a change that names it and says what it sends;
    - nothing sent beyond what the service needs.

    It lists the store and store update checks with their flags.
  - "ungoogled-chromium privacy defaults preserved" and "Changes to Chromium limited to hooks and identity" refer to that rule instead of naming the store.
  - "Google contacted only for store extensions" names the update service.

## Impact

- **Engine** (the engine key changes):
  - `patches/clair/restore-web-store.patch` gains hunks:
    - `CanUseUpdateService` sends store extensions to `UpdateService`, and only those whose update URL is the store's;
    - the update checker runs extension checks only;
    - store checks go to Google's JSON update address;
    - the flag handling ungoogled-chromium removed is put back (`OmahaAttributesHandler`, `ExtensionRegistrar`'s handlers, the call in `UpdateService`);
    - the request is stripped of the fields above.
  - A hook sends Chromium's blocklist alert to a new overlay file, which shows it as an extension prompt sheet.
- **`ClairHost.h` and `ClairUI`:** no change. The notice is a `ClairExtensionPromptKindOther` prompt with no cancel label, which `ExtensionPromptSheets` already shows as a one-button dialog.
- **Network:** store update checks move from `clients2.google.com/service/update2/crx` to `update.googleapis.com/service/update2/json`. Downloads come from the addresses the answer gives, as they do now.
- **Users:** an installed store extension Google has pulled is turned off at the next update check after updating Clair, and a malware one is announced. Rolling back leaves a flagged extension's state in its preferences. See design's Migration Plan.
- **Docs:** a Changie fragment. No doc in `docs/` describes the update path.
