# Spec Delta

## MODIFIED Requirements

### Requirement: ungoogled-chromium privacy defaults preserved
Clair SHALL ship ungoogled-chromium's default settings and Google-service removals unchanged, except for the password and autofill settings that Clair turns off, the Google services that "Google services Clair turns back on" allows, and the defaults that "Chromium safety defaults Clair restores" lists. Clair MUST NOT re-enable any other Google service integration that ungoogled-chromium removes or disables.

#### Scenario: Default settings match ungoogled-chromium
- **WHEN** a fresh Clair profile is compared with a fresh profile of the same ungoogled-chromium release
- **THEN** the defaults documented by ungoogled-chromium match, for example third-party cookies blocked, search suggestions disabled, and preload pages disabled, apart from the defaults "Chromium safety defaults Clair restores" lists

#### Scenario: No Google service traffic on an idle first launch
- **WHEN** Clair is launched for the first time with default settings and left on its new tab page with no user navigation
- **THEN** its only requests to Google are the certificate data check to Google's update service and the downloads it points to, and none go to Safe Browsing, sync, sign-in, metrics, extension updates or variations servers

#### Scenario: Google contacted only for store extensions
- **WHEN** the user has installed an extension from the Chrome Web Store
- **THEN** Clair contacts Google's extension servers and its extension update service only to download that extension and to check it for updates, and contacts no other Google service besides the certificate data check

#### Scenario: Component updater stays off
- **WHEN** a profile with store extensions has run its extension update checks
- **THEN** those checks named only extensions, and Clair has made no component update check besides the certificate data check

#### Scenario: Component updater checks only the revocation list
- **WHEN** Clair has run its component update checks
- **THEN** each check named only the certificate revocation list and the PKI metadata component, and no other component was checked, downloaded or updated

### Requirement: Browser behavior as in ungoogled-chromium outside Clair's interface
Apart from what Clair's own capabilities specify (`app-identity`, `native-layer`, `software-updates`, `browser-window`, `sidebar`, `command-bar`, `spaces`, `profiles`, `link-rules`, `extensions`) and the password and autofill features it turns off, Clair SHALL behave as its ungoogled-chromium release: page rendering, settings, `chrome://` pages, each profile's data, history, extensions' APIs, and the menus and shortcuts the native window keeps.

#### Scenario: Stock browser UI
- **WHEN** a user opens a window in a bare engine build
- **THEN** it shows Chromium's standard tab strip, toolbar and menus, as the same ungoogled-chromium release does on macOS

#### Scenario: Settings unchanged
- **WHEN** a user opens `chrome://settings` in the native window
- **THEN** it shows the same settings and defaults as the same ungoogled-chromium release, apart from Clair's identity and versions, the absent "Autofill and passwords" and "On startup" sections, and the defaults "Chromium safety defaults Clair restores" lists

#### Scenario: Links from other apps without rules
- **WHEN** Clair has no link rules and a link arrives from another app
- **THEN** it opens where the same ungoogled-chromium release would open it

### Requirement: Changes to Chromium limited to hooks and identity
Clair's patches to existing Chromium source files SHALL be limited to macOS build fixes, identity and branding, versioning, hooks, restoring the Google services that "Google services Clair turns back on" allows, and restoring the defaults that "Chromium safety defaults Clair restores" lists. That includes the code that acts on what those services return, routing their requests through the restored code, and limiting what they send. Other behaviour Clair adds SHALL live in the native layer or in new source files added to the Chromium tree.

#### Scenario: Reviewing Clair's patch series
- **WHEN** the patches in `patches/clair/` and `patches/helium/` are listed
- **THEN** each one is a build fix, an identity or branding change, a versioning change, a hook, the store and update restoration, or the restoration of listed safety defaults, and none implements the updater, the update menu or the native window

#### Scenario: Reviewing the store restoration
- **WHEN** a patch that restores a Google service is read
- **THEN** the service is on "Google services Clair turns back on"'s list, and each hunk puts back code that ungoogled-chromium's patches removed for it, routes its requests through that code, or removes data from what it sends, and adds no other behavior

#### Scenario: Reviewing a safety default restoration
- **WHEN** a patch that restores a Chromium safety default is read
- **THEN** the default is on "Chromium safety defaults Clair restores"'s list, and each hunk reverts part of an ungoogled-chromium patch, or sets the limit the list names, and adds no other behavior

## ADDED Requirements

### Requirement: Chromium safety defaults Clair restores
Clair SHALL revert an ungoogled-chromium change to Chromium's defaults only if the change weakens a security default, the revert contacts no Google service, and a change adds the default to this requirement's list. The rest of the ungoogled-chromium patch that made the change SHALL stay applied.

#### Scenario: The defaults Clair restores
- **WHEN** the Chromium safety defaults Clair restores are listed
- **THEN** they are the size limit on proxy auto-config downloads and secure DNS in automatic mode, and nothing else

#### Scenario: Proposing another default
- **WHEN** a change proposes reverting another ungoogled-chromium default
- **THEN** it says which security default the ungoogled-chromium change weakens and why ungoogled-chromium's reason doesn't hold for Clair, shows that the revert contacts no Google service, and adds the default to "The defaults Clair restores"

### Requirement: Proxy auto-config downloads bounded
Clair SHALL stop downloading a proxy auto-config file once it passes 16 MB and treat the download as failed, as Chromium does above its own limit. Smaller files SHALL load and apply as in Chromium.

#### Scenario: An oversized proxy auto-config file
- **WHEN** the proxy settings name a proxy auto-config file larger than 16 MB
- **THEN** Clair stops the download at the limit, doesn't apply the file, and connects as it does when a proxy auto-config file can't be fetched

#### Scenario: A large proxy auto-config file
- **WHEN** the proxy settings name a 2 MB proxy auto-config file
- **THEN** Clair loads it and routes requests as it says

### Requirement: Secure DNS automatic by default
Clair SHALL default secure DNS to Chromium's automatic mode with its mapping from DNS providers' addresses to their own DNS-over-HTTPS endpoints. It SHALL NOT offer or upgrade to Google's DNS-over-HTTPS endpoints. The user's choice in `chrome://settings/security` SHALL override the default.

#### Scenario: A known provider
- **WHEN** a fresh profile runs on a Mac whose DNS server is Cloudflare's 1.1.1.1
- **THEN** Clair resolves hosts over DNS over HTTPS with Cloudflare, and falls back to the system's DNS if that fails

#### Scenario: An unknown DNS server
- **WHEN** the Mac's DNS server isn't a known provider's
- **THEN** Clair resolves hosts with the system's DNS server, as before

#### Scenario: Google's DNS
- **WHEN** the Mac's DNS server is Google's 8.8.8.8
- **THEN** Clair resolves hosts with plain DNS to that server, and Google is not among the providers `chrome://settings/security` offers

#### Scenario: A user's choice kept
- **WHEN** a user turned secure DNS off or chose a provider before updating
- **THEN** Clair keeps that choice after updating

#### Scenario: Managed Macs
- **WHEN** machine-level browser policies are installed
- **THEN** Clair leaves automatic DNS over HTTPS off, as Chrome does, unless a policy turns it on
