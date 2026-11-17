# Spec Delta

## MODIFIED Requirements

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, and the Google services that "Google services Clair turns back on" allows. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

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
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, and restoring the Google services that "Google services Clair turns back on" allows. That includes the code that acts on what those services return, routing their requests through the restored code, and limiting what they send. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, or the store and update restoration, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing a service restoration
- **WHEN** a patch that restores a Google service is read
- **THEN** the service is on "Google services Clair turns back on"'s list, and each hunk puts back code that ungoogled-chromium's patches removed for it, routes its requests through that code, or removes data from what it sends, and adds no other behavior

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

## ADDED Requirements

### Requirement: Google services Clair turns back on
Clair SHALL turn back on a Google service that ungoogled-chromium removes or disables only if it is the Chrome Web Store or a feed that protects users from harm, such as flags on malware extensions or certificate revocation data. It SHALL do so only through a change that adds the service to this requirement's list. Each service SHALL send Google only what it needs to work, and no usage, activity, device or identifying data.

#### Scenario: The services Clair turns back on
- **WHEN** the Google services Clair turns back on are listed
- **THEN** they are the Chrome Web Store's pages and installs, and store extension update checks with the flags they return, and nothing else

#### Scenario: Proposing another service
- **WHEN** a change proposes turning on another Google service that ungoogled-chromium removes
- **THEN** the service is the store's or protects users from harm, the change says what each request sends and why each field is needed, and it adds the service to "The services Clair turns back on"

#### Scenario: A convenience service
- **WHEN** a Google service would only add convenience, such as sync, sign-in, translation, field trials or downloading media components
- **THEN** this requirement doesn't allow it, and turning it on needs a change that amends this requirement first

#### Scenario: What a turned-on service sends
- **WHEN** a request from a service on the list is captured
- **THEN** it carries only the fields its change named, and no install or device identifiers, usage pings or hardware and OS details beyond the platform and architecture
