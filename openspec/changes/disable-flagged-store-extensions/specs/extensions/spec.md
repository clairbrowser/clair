# Spec Delta

## MODIFIED Requirements

### Requirement: Extensions update automatically
Clair SHALL check for updates to installed extensions whose update URL is the Chrome Web Store's, or that set their own, and SHALL install the updates, as Chrome does. Store extensions SHALL be checked with Google's extension update service, and other extensions with their own update server. A profile with no such extensions SHALL make no update requests.

#### Scenario: A newer version is published
- **WHEN** a store extension is installed and the store publishes a newer version
- **THEN** Clair installs the newer version at its next update check without the user doing anything

#### Scenario: No store extensions
- **WHEN** a profile has no extensions with an update URL
- **THEN** Clair makes no extension update requests to Google

#### Scenario: Extension with its own update server
- **WHEN** an installed extension's update URL names a server other than the store's
- **THEN** Clair checks it with that server only, and the check doesn't reach Google

## ADDED Requirements

### Requirement: What a store update check sends
A store update check SHALL send only each extension's ID, version, install source and the hash of its cached store package, Clair's Chromium version, channel and language, the platform and architecture, and random per-request IDs. It SHALL NOT send the macOS version, hardware details, install dates or IDs, cohorts, enabled state or activity data, and Clair SHALL send no report after an install or update.

#### Scenario: Reading a store update check
- **WHEN** a profile with a store extension checks for updates and the request is captured
- **THEN** its body names the extension's ID, version and install source, the Chromium version, channel, language, `mac` and `arm64`, and none of the fields this requirement rules out

#### Scenario: Update as a patch
- **WHEN** a store extension that Clair last downloaded through an update check gets a newer version
- **THEN** the check names the hash of the package Clair already has, and Clair installs the update from a patch to it when the store offers one, or from the full package when it doesn't

#### Scenario: After an update installs
- **WHEN** a store update check finds a newer version and Clair installs it
- **THEN** Clair sends no further request to Google about the install

### Requirement: Store-flagged extensions turned off
When a store update check reports that an installed extension is malware, Clair SHALL unload it, and the user SHALL only be able to remove it. When it reports a policy violation or a potentially unwanted extension, Clair SHALL turn the extension off, with Chromium's reason shown in `chrome://extensions`, and the user MAY turn it back on. When a later check clears the flag, Clair SHALL restore the extension as Chrome does.

#### Scenario: Malware
- **WHEN** an installed store extension is reported as malware at an update check
- **THEN** it stops running, its button leaves the sidebar and the Extensions menu, and `chrome://extensions` lists it as malware with no way to turn it on

#### Scenario: Policy violation
- **WHEN** an installed store extension is reported as violating the store's policy
- **THEN** it's turned off, `chrome://extensions` gives that reason, and the user can turn it back on there

#### Scenario: Turned back on by the user
- **WHEN** the user has turned a policy-violation extension back on and the next check reports the same flag
- **THEN** the extension stays on

#### Scenario: Flag cleared
- **WHEN** a check no longer reports the malware flag for an extension Clair unloaded for it
- **THEN** the extension is loaded again, as it was before

### Requirement: Notice for malware extensions
When Clair unloads an extension for malware, it SHALL tell the user in a Clair dialog (`dialogs`) on the frontmost browser window, using Chromium's wording, with a single OK button. One dialog SHALL name every extension unloaded for malware that the user hasn't yet been told about. Policy-violation and potentially unwanted extensions SHALL be turned off without a dialog, as in Chrome.

#### Scenario: One extension found
- **WHEN** an installed extension is unloaded for malware while a browser window is open
- **THEN** a dialog on that window says Clair found that the extension contains malware, and OK closes it

#### Scenario: Told once
- **WHEN** the user has closed the dialog for an extension and Clair is relaunched
- **THEN** no dialog about that extension appears again

#### Scenario: No window open
- **WHEN** an extension is unloaded for malware while no browser window is open
- **THEN** the dialog appears on the next browser window that opens
