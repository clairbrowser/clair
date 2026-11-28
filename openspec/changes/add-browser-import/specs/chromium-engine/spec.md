# Spec Delta

## MODIFIED Requirements

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from what Clair's own capabilities specify (`app-identity`, `native-layer`, `software-updates`, `browser-window`, `sidebar`, `command-bar`, `spaces`, `profiles`, `link-rules`, `extensions`, `browser-import`) and the password and autofill features it turns off, Clair SHALL behave as its ungoogled-chromium release: page rendering, settings, `chrome://` pages, each profile's data, history, extensions' APIs, and the menus and shortcuts the native window keeps.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions, the absent "Autofill and passwords" and "On startup" sections, and the absent "Import bookmarks and settings" row

#### Scenario: Links from other apps without rules
- **WHEN** Clair has no link rules and a link arrives from another app
- **THEN** it opens where the same ungoogled-chromium release would open it

### Requirement: What Clair's Chromium hooks may do
Each of Clair's hooks SHALL only redirect to Clair's code or switch a Chromium feature off. The hooks load the native layer, hand browser windows and extension alerts to Clair, register its component extensions and preferences, tag its tabs in saved sessions, free its shortcuts, turn off or hide passwords, autofill, extensions' uninstall pages and Chromium's importer, restore the last session by default, and offer links from other apps to its link rules first.

#### Scenario: Reviewing a window hook
- **WHEN** a hunk of the native-window hook patch is read
- **THEN** it calls into Clair's overlay files or the native layer, makes Chromium skip UI the native window replaces, or switches off a feature Clair removes, and any behavior is in Clair's files

#### Scenario: Reviewing a session hook
- **WHEN** a hunk of a patch to Chromium's session code is read
- **THEN** it calls into Clair's overlay files to write or read a tag on a tab, and decides nothing itself

#### Scenario: Reviewing the link rules hook
- **WHEN** the hunk that hooks links from other apps is read
- **THEN** it hands each link to Clair's overlay files and opens only the links they leave, as Chromium would, and decides nothing itself

#### Scenario: Reviewing the extension alert hook
- **WHEN** the hunk that hooks Chromium's blocklisted-extension alert is read
- **THEN** it hands the alert to Clair's overlay files, and decides nothing itself

#### Scenario: Reviewing the importer hook
- **WHEN** a hunk of the patch that turns off Chromium's importer is read
- **THEN** it removes the importer's settings route, row or menu entry, and adds no other behavior
