# Spec Delta

## MODIFIED Requirements

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, and the Chrome Web Store installs and extension update checks that `extensions` restores. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** it makes no network requests to Google service endpoints, such as Safe Browsing, sync, sign-in, metrics, extension updates, or component and variations servers

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers and its extension update service only to download that extension and to check it for updates, and no other Google service

#### Scenario: Component updater stays off
- **WHEN** a profile with store extensions has run its extension update checks
- **THEN** Clair has made no component update check

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, and restoring what the Chrome Web Store needs that ungoogled-chromium removes: the installer, extension update checks, and acting on the flags those checks return. That includes sending store checks through the restored code and limiting what they send. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, or the store and update restoration, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing the store restoration
- **WHEN** the patch that restores the Chrome Web Store is read
- **THEN** each hunk puts back code that ungoogled-chromium's patches removed for the store installer, for extension update checks or for acting on their flags, sends store update checks through that code, or removes data from what those checks send, and adds no other behavior

### Requirement: What Clair's Chromium hooks may do
Clair's hooks SHALL load the native layer, hand Chromium's browser windows and extension alerts to Clair's code, register Clair's component extensions and preferences, tag Clair's tabs in saved sessions and read them back, free Clair's shortcuts, turn off or hide the password and autofill features and extensions' uninstall pages, restore the last session by default, and offer links from other apps to Clair's link rules first. Each hook SHALL only redirect to Clair's code or switch a Chromium feature off.

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
